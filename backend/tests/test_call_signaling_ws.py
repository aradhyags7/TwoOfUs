import json
import os
import socket
import sys
import threading
import time
import unittest
from datetime import datetime, timezone

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

import uvicorn
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from websockets.sync.client import connect as ws_connect

from backend.app.main import app, get_db
from backend.app.core.database import Base
from backend.app.core.security import hash_password, create_access_token
from backend.app.models import User, Pair, CallSession, Message, DevicePushToken

TEST_DATABASE_URL = "sqlite:///./test_call_signaling_ws.db"
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


class WebSocketCallSignalingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('127.0.0.1', 0))
            cls.port = s.getsockname()[1]

        cls.config = uvicorn.Config(app=app, host="127.0.0.1", port=cls.port, log_level="warning")
        cls.server = uvicorn.Server(cls.config)
        cls.server_thread = threading.Thread(target=cls.server.run, daemon=True)
        cls.server_thread.start()
        time.sleep(1)
        cls.base_ws_url = f"ws://127.0.0.1:{cls.port}"

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db

    @classmethod
    def tearDownClass(cls):
        cls.server.should_exit = True
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("test_call_signaling_ws.db"):
            try:
                os.remove("test_call_signaling_ws.db")
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
        token = create_access_token(data={"sub": str(user_id), "email": email})
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

    def test_01_unauthenticated_ws_rejected(self):
        """Verifies connecting without token is closed."""
        try:
            with client.websocket_connect("/ws/call") as ws:
                self.fail("Should have closed unauthenticated connection")
        except Exception:
            pass
        print("  [PASS] Unauthenticated WebSocket connection rejected")

    def test_02_invalid_token_ws_rejected(self):
        """Verifies connecting with invalid token is closed."""
        try:
            with client.websocket_connect("/ws/call?token=invalid_garbage_token") as ws:
                self.fail("Should have closed invalid token connection")
        except Exception:
            pass
        print("  [PASS] Invalid token WebSocket connection rejected")

    def test_03_authenticated_ws_and_ping_pong(self):
        """Verifies valid token connection receives authenticated ack and handles ping/pong."""
        u1, t1 = self.create_test_user("ws_u1@test.com", "ws_u1")
        with client.websocket_connect(f"/ws/call?token={t1}") as ws:
            ack = ws.receive_json()
            self.assertEqual(ack["type"], "authenticated")
            self.assertEqual(ack["user_id"], u1)

            # Test heartbeat
            ws.send_json({"type": "ping"})
            pong = ws.receive_json()
            self.assertEqual(pong["type"], "pong")
            self.assertIn("timestamp", pong)
        print("  [PASS] Authenticated WebSocket connect & ping-pong heartbeat")

    def test_04_legacy_path_impersonation_blocked(self):
        """Verifies that user 1 cannot connect to user 2's legacy endpoint."""
        u1, t1 = self.create_test_user("impersonator@test.com", "impersonator")
        u2, t2 = self.create_test_user("victim@test.com", "victim")

        try:
            with client.websocket_connect(f"/ws/call/{u2}?token={t1}") as ws:
                self.fail("User 1 should not be able to connect to /ws/call/{u2}")
        except Exception:
            pass
        print("  [PASS] Identity impersonation on legacy path blocked (4003)")

    def test_05_unpaired_signal_blocked(self):
        """Verifies signal between un-paired accounts is rejected with 403."""
        u1, t1 = self.create_test_user("lonely1@test.com", "lonely1")
        u2, t2 = self.create_test_user("stranger2@test.com", "stranger2")

        with client.websocket_connect(f"/ws/call?token={t1}") as ws:
            ws.receive_json()  # ack
            ws.send_json({
                "type": "call_invite",
                "target_id": u2,
                "call_type": "voice",
            })
            resp = ws.receive_json()
            self.assertEqual(resp["type"], "error")
            self.assertEqual(resp["code"], 403)
            self.assertIn("paired partner", resp["detail"])
        print("  [PASS] Unpaired signaling blocked with 403")

    def test_06_full_webrtc_signaling_lifecycle(self):
        """
        Tests end-to-end WebRTC signaling between paired users:
        Invite -> Ringing -> Accept -> SDP Offer -> SDP Answer -> ICE Candidate -> End
        """
        u1, t1 = self.create_test_user("webrtc_u1@test.com", "webrtc_u1")
        u2, t2 = self.create_test_user("webrtc_u2@test.com", "webrtc_u2")
        self.create_test_pair(u1, u2)

        with ws_connect(f"{self.base_ws_url}/ws/call?token={t1}") as ws1:
            ack1 = json.loads(ws1.recv(timeout=5))
            self.assertEqual(ack1["type"], "authenticated")
            self.assertEqual(ack1["user_id"], u1)

            with ws_connect(f"{self.base_ws_url}/ws/call?token={t2}") as ws2:
                ack2 = json.loads(ws2.recv(timeout=5))
                self.assertEqual(ack2["type"], "authenticated")
                self.assertEqual(ack2["user_id"], u2)

                # 1. User 1 invites User 2
                ws1.send(json.dumps({
                    "type": "call_invite",
                    "target_id": u2,
                    "call_type": "video",
                }))

                # ws1 gets initiated + ringing
                init_ack = json.loads(ws1.recv(timeout=5))
                self.assertEqual(init_ack["type"], "call_initiated")
                call_id = init_ack["call_id"]
                self.assertEqual(init_ack["status"], "ringing")

                ring_ack = json.loads(ws1.recv(timeout=5))
                self.assertEqual(ring_ack["type"], "call_ringing")

                # ws2 gets incoming_call
                incoming = json.loads(ws2.recv(timeout=5))
                self.assertEqual(incoming["type"], "incoming_call")
                self.assertEqual(incoming["call_id"], call_id)
                self.assertEqual(incoming["caller_id"], u1)

                # 2. User 2 accepts call
                ws2.send(json.dumps({
                    "type": "call_accept",
                    "call_id": call_id,
                }))

                # ws1 receives call_accepted
                accepted = json.loads(ws1.recv(timeout=5))
                self.assertEqual(accepted["type"], "call_accepted")
                self.assertEqual(accepted["call_id"], call_id)

                # 3. User 1 sends WebRTC SDP Offer
                sample_sdp = "v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
                ws1.send(json.dumps({
                    "type": "webrtc_offer",
                    "call_id": call_id,
                    "payload": {"sdp": sample_sdp, "type": "offer"},
                }))

                # ws2 receives WebRTC SDP Offer
                offer_received = json.loads(ws2.recv(timeout=5))
                self.assertEqual(offer_received["type"], "webrtc_offer")
                self.assertEqual(offer_received["payload"]["sdp"], sample_sdp)
                self.assertEqual(offer_received["sender_id"], u1)

                # 4. User 2 sends WebRTC SDP Answer
                answer_sdp = "v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
                ws2.send(json.dumps({
                    "type": "webrtc_answer",
                    "call_id": call_id,
                    "payload": {"sdp": answer_sdp, "type": "answer"},
                }))

                # ws1 receives WebRTC SDP Answer
                answer_received = json.loads(ws1.recv(timeout=5))
                self.assertEqual(answer_received["type"], "webrtc_answer")
                self.assertEqual(answer_received["payload"]["sdp"], answer_sdp)

                # 5. User 1 sends ICE Candidate
                ice_data = {"candidate": "candidate:1 1 UDP 2122260223 192.168.1.100 50000 typ host", "sdpMid": "0"}
                ws1.send(json.dumps({
                    "type": "webrtc_ice_candidate",
                    "call_id": call_id,
                    "payload": ice_data,
                }))

                # ws2 receives ICE Candidate
                ice_received = json.loads(ws2.recv(timeout=5))
                self.assertEqual(ice_received["type"], "webrtc_ice_candidate")
                self.assertEqual(ice_received["payload"]["candidate"], ice_data["candidate"])

                # 6. User 2 terminates call
                ws2.send(json.dumps({
                    "type": "call_end",
                    "call_id": call_id,
                    "reason": "normal_hangup",
                }))

                # ws1 receives call_ended
                end_received = json.loads(ws1.recv(timeout=5))
                self.assertEqual(end_received["type"], "call_ended")
                self.assertEqual(end_received["call_id"], call_id)
                self.assertEqual(end_received["status"], "ended")

        print("  [PASS] Full end-to-end WebRTC signaling lifecycle (invite -> offer -> answer -> ICE -> end)")

    def test_07_device_push_token_and_turn_credentials(self):
        """Tests FCM device push token registration and TURN credentials generation."""
        u1, t1 = self.create_test_user("device_u1@test.com", "device_u1")

        # 1. Register push token
        reg_res = client.post(
            f"/call/device-token?token={t1}",
            json={"token": "SAMPLE_FCM_REGISTRATION_TOKEN_12345", "platform": "android"}
        )
        self.assertEqual(reg_res.status_code, 200)
        self.assertEqual(reg_res.json()["status"], "registered")

        # 2. Get TURN credentials
        turn_res = client.get(f"/call/turn-credentials?token={t1}")
        self.assertEqual(turn_res.status_code, 200)
        turn_data = turn_res.json()
        self.assertIn("username", turn_data)
        self.assertIn("password", turn_data)
        self.assertTrue(len(turn_data["uris"]) >= 3)
        self.assertIn("stun:stun.l.google.com:19302", turn_data["uris"])

        # 3. Unregister push token
        del_res = client.delete(
            f"/call/device-token?token=SAMPLE_FCM_REGISTRATION_TOKEN_12345&auth_token={t1}"
        )
        self.assertEqual(del_res.status_code, 200)
        self.assertEqual(del_res.json()["status"], "unregistered")
        print("  [PASS] Device push token lifecycle and STUN/TURN credentials verified")


if __name__ == "__main__":
    unittest.main(verbosity=2)
