import os
import sys
import io
import time
import uuid
import threading
import unittest

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

from datetime import datetime, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from backend.app.main import app, get_db
from backend.app.core.database import Base
from backend.app.core.security import hash_password, create_access_token
from backend.app.models import User, Pair, Message, Media, ConnectionPin

# Use an isolated test database
SQLALCHEMY_DATABASE_URL = "sqlite:///./test_security_audit.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

class SecurityPenetrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

    @classmethod
    def tearDownClass(cls):
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("./test_security_audit.db"):
            try:
                os.remove("./test_security_audit.db")
            except Exception:
                pass

    def create_test_user(self, email: str, username: str, password: str = "Password123!") -> tuple[int, str]:
        db = TestingSessionLocal()
        user = User(
            email=email,
            username=username,
            password_hash=hash_password(password),
            public_key=f"pubkey_mock_{username}"
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        uid = int(user.id)
        token = create_access_token({"sub": str(uid), "email": email})
        db.close()
        return uid, token

    def create_test_pair(self, u1: int, u2: int) -> int:
        db = TestingSessionLocal()
        pair = Pair(user1_id=u1, user2_id=u2, connection_pin=f"PIN_{uuid.uuid4().hex[:8]}")
        db.add(pair)
        db.commit()
        db.refresh(pair)
        pid = int(pair.id)
        db.close()
        return pid

    # --------------------------------------------------------------------------
    # 1. Unauthenticated Endpoint Access Tests
    # --------------------------------------------------------------------------
    def test_01_unauthenticated_requests_blocked(self):
        self.assertEqual(client.get("/me").status_code, 401)
        self.assertEqual(client.get("/messages/1/2").status_code, 401)
        self.assertEqual(client.post("/send-message", json={"sender_id": 1, "receiver_id": 2, "content": "hi"}).status_code, 401)
        self.assertEqual(client.delete("/messages/1").status_code, 401)
        self.assertEqual(client.put("/messages/1", json={"content": "edited"}).status_code, 401)
        self.assertEqual(client.get("/profile/1").status_code, 401)
        self.assertEqual(client.put("/profile/1", json={"username": "hacked"}).status_code, 401)
        self.assertEqual(client.put("/change-password/1", json={"current_password": "a", "new_password": "b"}).status_code, 401)
        self.assertEqual(client.get("/generate-pin/1").status_code, 401)
        self.assertEqual(client.post("/connect-by-pin", json={"user_id": 1, "pin_code": "1234"}).status_code, 401)
        self.assertEqual(client.get("/keys/1").status_code, 401)
        self.assertEqual(client.get("/media/1/file").status_code, 401)
        print("  [PASS] All sensitive endpoints reject unauthenticated access (401)")

    # --------------------------------------------------------------------------
    # 2. Cross-User Impersonation / IDOR Tests
    # --------------------------------------------------------------------------
    def test_02_cross_user_impersonation_blocked(self):
        u1, t1 = self.create_test_user("alice@twoofus.app", "alice")
        u2, t2 = self.create_test_user("bob@twoofus.app", "bob")
        u3, t3 = self.create_test_user("charlie@twoofus.app", "charlie")
        self.create_test_pair(u1, u2)

        headers_charlie = {"Authorization": f"Bearer {t3}"}

        # Charlie tries to send message claiming to be Alice -> 403 Forbidden
        res = client.post(
            "/send-message",
            json={"sender_id": u1, "receiver_id": u2, "content": "spoofed message"},
            headers=headers_charlie
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("Sender ID does not match", res.json()["detail"])

        # Charlie tries to read Alice & Bob's conversation -> 403 Forbidden
        res = client.get(f"/messages/{u1}/{u2}", headers=headers_charlie)
        self.assertEqual(res.status_code, 403)

        # Charlie tries to update Alice's profile -> 403 Forbidden
        res = client.put(f"/profile/{u1}", json={"username": "hacked_alice"}, headers=headers_charlie)
        self.assertEqual(res.status_code, 403)

        # Charlie tries to change Alice's password -> 403 Forbidden
        res = client.put(
            f"/change-password/{u1}",
            json={"current_password": "Password123!", "new_password": "NewHackedPassword1!"},
            headers=headers_charlie
        )
        self.assertEqual(res.status_code, 403)

        # Charlie tries to generate PIN for Alice -> 403 Forbidden
        res = client.get(f"/generate-pin/{u1}", headers=headers_charlie)
        self.assertEqual(res.status_code, 403)
        print("  [PASS] IDOR & Impersonation attempts strictly blocked (403)")

    # --------------------------------------------------------------------------
    # 3. View Once Concurrency & Physical Shredding Tests
    # --------------------------------------------------------------------------
    def test_03_view_once_atomic_concurrency_and_file_shredding(self):
        u1, t1 = self.create_test_user("vo_sender@twoofus.app", "vo_sender")
        u2, t2 = self.create_test_user("vo_receiver@twoofus.app", "vo_receiver")
        self.create_test_pair(u1, u2)

        headers_sender = {"Authorization": f"Bearer {t1}"}
        headers_receiver = {"Authorization": f"Bearer {t2}"}

        # Upload View Once Encrypted Media
        fake_ciphertext = b"\x00\x01\x02\x03\x04\x05CIPHERTEXT_MOCK_PAYLOAD\xfe\xff"
        upload_res = client.post(
            "/media/upload",
            data={
                "receiver_id": str(u2),
                "is_encrypted": "true",
                "is_view_once": "true",
                "encrypted_media_key": '{"k":"key","n":"nonce"}',
                "encryption_nonce": "nonceBase64==",
            },
            files=[("files", ("photo.jpg", io.BytesIO(fake_ciphertext), "image/jpeg"))],
            headers=headers_sender
        )
        self.assertEqual(upload_res.status_code, 200)
        media_id = upload_res.json()[0]["media_id"]

        # Verify physical file exists on disk prior to consumption
        db = TestingSessionLocal()
        media_rec = db.query(Media).filter(Media.id == media_id).first()
        self.assertIsNotNone(media_rec)
        storage_path = str(media_rec.storage_path) if media_rec and media_rec.storage_path else ""
        self.assertTrue(os.path.exists(storage_path))
        db.close()

        # Simulate 20 Concurrent Download Requests
        results = []
        def worker():
            r = client.get(f"/media/{media_id}/file", headers=headers_receiver)
            results.append(r.status_code)

        threads = [threading.Thread(target=worker) for _ in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        success_count = results.count(200)
        gone_count = results.count(410)

        self.assertEqual(success_count, 1, f"Expected exactly 1 success, got {success_count}")
        self.assertEqual(gone_count, 19, f"Expected 19 HTTP 410 Gone, got {gone_count}")

        # Verify physical file was shredded from disk
        self.assertFalse(os.path.exists(storage_path), "Physical View Once file was not deleted from disk!")

        # Followup attempt returns 410 Gone
        followup_res = client.get(f"/media/{media_id}/file", headers=headers_receiver)
        self.assertEqual(followup_res.status_code, 410)
        print("  [PASS] View Once 20-thread concurrency race condition test: 1x 200 OK, 19x 410 Gone, 0 leaks on disk")

    # --------------------------------------------------------------------------
    # 4. Zero-Knowledge Media Storage & Path Traversal Tests
    # --------------------------------------------------------------------------
    def test_04_zero_knowledge_storage_and_metadata_sanitization(self):
        u1, t1 = self.create_test_user("zk_u1@twoofus.app", "zk_u1")
        u2, t2 = self.create_test_user("zk_u2@twoofus.app", "zk_u2")
        self.create_test_pair(u1, u2)

        headers_sender = {"Authorization": f"Bearer {t1}"}

        sensitive_filename = "IMG_20260819_PRIVATE_CAMERA_GPS_METADATA.jpg"
        raw_ciphertext = b"GENUINE_ENCRYPTED_CIPHERTEXT_ONLY_998811"

        upload_res = client.post(
            "/media/upload",
            data={
                "receiver_id": str(u2),
                "is_encrypted": "true",
                "is_view_once": "false",
            },
            files=[("files", (sensitive_filename, io.BytesIO(raw_ciphertext), "image/jpeg"))],
            headers=headers_sender
        )
        self.assertEqual(upload_res.status_code, 200)
        media_info = upload_res.json()[0]

        # Sanitized filename
        self.assertNotIn(sensitive_filename, media_info["original_filename"])
        self.assertTrue(media_info["original_filename"].startswith("enc_"))
        self.assertIsNone(media_info["thumbnail_path"])

        # Check raw disk bytes
        db = TestingSessionLocal()
        media_rec = db.query(Media).filter(Media.id == media_info["media_id"]).first()
        self.assertIsNotNone(media_rec)
        if media_rec and media_rec.storage_path:
            with open(str(media_rec.storage_path), "rb") as f:
                stored_bytes = f.read()
            self.assertEqual(stored_bytes, raw_ciphertext)
        db.close()
        print("  [PASS] Zero-knowledge storage: filename sanitized, no server thumbnail generated, only ciphertext stored on disk")

    def test_05_executable_uploads_blocked(self):
        u1, t1 = self.create_test_user("traversal_u1@twoofus.app", "traversal_u1")
        u2, t2 = self.create_test_user("traversal_u2@twoofus.app", "traversal_u2")
        self.create_test_pair(u1, u2)

        headers_sender = {"Authorization": f"Bearer {t1}"}

        malicious_res = client.post(
            "/media/upload",
            data={"receiver_id": str(u2)},
            files=[("files", ("virus.exe", io.BytesIO(b"MZ..."), "application/x-msdownload"))],
            headers=headers_sender
        )
        self.assertEqual(malicious_res.status_code, 415)
        self.assertIn("strictly prohibited", malicious_res.json()["detail"])
        print("  [PASS] Executable file upload blocked with HTTP 415")


if __name__ == "__main__":
    unittest.main(verbosity=2)
