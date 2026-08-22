import os
import sys
import unittest
from datetime import datetime, timezone

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from backend.app.main import app, get_db
from backend.app.core.database import Base
from backend.app.core.security import hash_password, create_access_token
from backend.app.models import User, Pair, CallSession, Message

TEST_DATABASE_URL = "sqlite:///./test_call_signaling.db"
engine = create_engine(TEST_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

class CallSignalingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)

    @classmethod
    def tearDownClass(cls):
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("test_call_signaling.db"):
            try:
                os.remove("test_call_signaling.db")
            except Exception:
                pass

    def create_test_user(self, email: str, username: str) -> tuple[int, str]:
        db = TestingSessionLocal()
        user = User(
            email=email,
            username=username,
            password_hash=hash_password("Pass123!"),
            public_key="TEST_PUB_KEY"
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        user_id = int(getattr(user, "id"))
        db.close()
        token = str(create_access_token(data={"sub": str(user_id), "email": email}))
        return user_id, token

    def create_test_pair(self, user1_id: int, user2_id: int):
        db = TestingSessionLocal()
        pair = Pair(
            user1_id=user1_id,
            user2_id=user2_id,
            connection_pin=f"PIN_{user1_id}_{user2_id}"
        )
        db.add(pair)
        db.commit()
        db.close()

    def test_01_unpaired_call_blocked(self):
        u1, t1 = self.create_test_user("caller1@test.com", "caller1")
        u2, t2 = self.create_test_user("stranger1@test.com", "stranger1")

        headers = {"Authorization": f"Bearer {t1}"}
        res = client.post("/call/initiate", json={"receiver_id": u2, "call_type": "voice"}, headers=headers)
        self.assertEqual(res.status_code, 403)
        self.assertIn("only call your paired partner", res.json()["detail"])
        print("  [PASS] Unauthorized calling between un-paired accounts blocked (403)")

    def test_02_voice_call_full_lifecycle(self):
        u1, t1 = self.create_test_user("call_u1@test.com", "call_u1")
        u2, t2 = self.create_test_user("call_u2@test.com", "call_u2")
        self.create_test_pair(u1, u2)

        h1 = {"Authorization": f"Bearer {t1}"}
        h2 = {"Authorization": f"Bearer {t2}"}

        # 1. Caller initiates voice call
        init_res = client.post("/call/initiate", json={"receiver_id": u2, "call_type": "voice"}, headers=h1)
        self.assertEqual(init_res.status_code, 200)
        call_data = init_res.json()
        call_id = call_data["id"]
        self.assertEqual(call_data["status"], "ringing")
        self.assertEqual(call_data["call_type"], "voice")

        # 2. Check active call for receiver
        active_res = client.get(f"/call/active/{u2}", headers=h2)
        self.assertEqual(active_res.status_code, 200)
        self.assertIsNotNone(active_res.json())
        self.assertEqual(active_res.json()["id"], call_id)

        # 3. Receiver accepts call
        accept_res = client.post("/call/respond", json={"call_id": call_id, "action": "accept"}, headers=h2)
        self.assertEqual(accept_res.status_code, 200)
        self.assertEqual(accept_res.json()["status"], "ongoing")
        self.assertIsNotNone(accept_res.json()["started_at"])

        # 4. End call
        end_res = client.post("/call/end", json={"call_id": call_id}, headers=h1)
        self.assertEqual(end_res.status_code, 200)
        self.assertEqual(end_res.json()["status"], "ended")
        self.assertIsNotNone(end_res.json()["ended_at"])

        # 5. Check call history
        history_res = client.get(f"/call/history/{u2}", headers=h1)
        self.assertEqual(history_res.status_code, 200)
        history = history_res.json()
        self.assertTrue(len(history) >= 1)
        self.assertEqual(history[0]["id"], call_id)
        print("  [PASS] Voice call complete lifecycle: initiate -> active check -> accept -> end -> history")

    def test_03_video_call_rejection(self):
        u1, t1 = self.create_test_user("vcall_u1@test.com", "vcall_u1")
        u2, t2 = self.create_test_user("vcall_u2@test.com", "vcall_u2")
        self.create_test_pair(u1, u2)

        h1 = {"Authorization": f"Bearer {t1}"}
        h2 = {"Authorization": f"Bearer {t2}"}

        # 1. Initiate video call
        init_res = client.post("/call/initiate", json={"receiver_id": u2, "call_type": "video"}, headers=h1)
        self.assertEqual(init_res.status_code, 200)
        call_id = init_res.json()["id"]
        self.assertEqual(init_res.json()["call_type"], "video")

        # 2. Reject call
        rej_res = client.post("/call/respond", json={"call_id": call_id, "action": "reject"}, headers=h2)
        self.assertEqual(rej_res.status_code, 200)
        self.assertEqual(rej_res.json()["status"], "rejected")

        # 3. Active call should now be None
        active_res = client.get(f"/call/active/{u1}", headers=h1)
        self.assertEqual(active_res.status_code, 200)
        self.assertIsNone(active_res.json())

        # 4. Check conversation messages contains CALL_LOG
        msg_res = client.get(f"/messages/{u1}/{u2}", headers=h1)
        self.assertEqual(msg_res.status_code, 200)
        msgs = msg_res.json()
        call_logs = [m for m in msgs if m["content"].startswith("CALL_LOG:")]
        self.assertTrue(len(call_logs) >= 1)
        self.assertIn('"status": "rejected"', call_logs[0]["content"])
        self.assertIn('"call_type": "video"', call_logs[0]["content"])
        print("  [PASS] Video call rejection lifecycle & chat log verified")


if __name__ == "__main__":
    unittest.main(verbosity=2)

