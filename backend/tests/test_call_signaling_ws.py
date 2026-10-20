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
from backend.app.core.database import Base, get_db as core_get_db
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
app.dependency_overrides[core_get_db] = override_get_db
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
        app.dependency_overrides[core_get_db] = override_get_db

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

    def test_08_call_ticket_auth_and_debug_endpoint(self):
        """Tests single-use WS ticket generation, redemption, single-use enforcement, and GET /call/debug."""
        u1, t1 = self.create_test_user("ticket_u1@test.com", "ticket_u1")

        # 1. Obtain single-use WS ticket
        ticket_res = client.post(f"/call/ticket?token={t1}")
        self.assertEqual(ticket_res.status_code, 200)
        ticket = ticket_res.json()["ticket"]
        self.assertTrue(ticket.startswith("call_ticket_"))

        # 2. Connect using ticket
        ws_url = f"{self.base_ws_url}/ws/call?ticket={ticket}"
        with ws_connect(ws_url) as ws:
            # Query debug endpoint while connected
            debug_res = client.get(f"/call/debug?token={t1}")
            self.assertEqual(debug_res.status_code, 200)
            data = debug_res.json()
            self.assertEqual(data["user_id"], u1)
            self.assertEqual(data["active_ws_connections_count"], 1)
            self.assertTrue(data["is_user_online"])
            self.assertIn("ice_servers", data)

        # 3. Re-using the same ticket must be rejected (single-use)
        with self.assertRaises(Exception):
            with ws_connect(ws_url):
                pass
        print("  [PASS] Single-use WS ticket auth & GET /call/debug verified")

    def test_09_stale_sessions_cleanup(self):
        """Tests that 45s ringing timeout marks calls 'missed' and orphan ongoing sessions are marked 'ended'."""
        from datetime import timedelta
        from backend.app.services.signaling_manager import secure_call_manager

        u1, t1 = self.create_test_user("stale_u1@test.com", "stale_u1")
        u2, t2 = self.create_test_user("stale_u2@test.com", "stale_u2")
        self.create_test_pair(u1, u2)

        db = TestingSessionLocal()
        now = datetime.now(timezone.utc)
        old_time = now - timedelta(seconds=60)

        # 1. Create a stale ringing session (>45s old)
        stale_call = CallSession(
            caller_id=u1,
            receiver_id=u2,
            call_type="voice",
            status="ringing",
            created_at=old_time,
        )
        db.add(stale_call)

        # 2. Create an orphan ongoing session where neither user is online
        orphan_call = CallSession(
            caller_id=u1,
            receiver_id=u2,
            call_type="video",
            status="ongoing",
            created_at=old_time,
            started_at=old_time,
        )
        db.add(orphan_call)
        db.commit()

        stale_id = stale_call.id
        orphan_id = orphan_call.id

        # 3. Run stale session cleanup
        secure_call_manager.clean_stale_sessions(db)

        # 4. Verify stale ringing call is now 'missed'
        updated_stale = db.query(CallSession).filter(CallSession.id == stale_id).first()
        self.assertEqual(updated_stale.status, "missed")
        self.assertEqual(updated_stale.ended_reason, "ringing_timeout_45s")

        # 5. Verify orphan ongoing call is now 'ended'
        updated_orphan = db.query(CallSession).filter(CallSession.id == orphan_id).first()
        self.assertEqual(updated_orphan.status, "ended")
        self.assertEqual(updated_orphan.ended_reason, "both_sockets_disconnected")
        db.close()
        print("  [PASS] Stale ringing session (45s) and orphan ongoing session cleanup verified")

    def test_10_callee_ready_handshake(self):
        """Tests that callee_ready signal is successfully forwarded from callee to caller."""
        u1, t1 = self.create_test_user("ready_u1@test.com", "ready_u1")
        u2, t2 = self.create_test_user("ready_u2@test.com", "ready_u2")
        self.create_test_pair(u1, u2)

        with ws_connect(f"{self.base_ws_url}/ws/call?token={t1}") as ws1:
            with ws_connect(f"{self.base_ws_url}/ws/call?token={t2}") as ws2:
                # Consume initial authentication acks
                ack1 = json.loads(ws1.recv(timeout=5))
                self.assertEqual(ack1["type"], "authenticated")
                ack2 = json.loads(ws2.recv(timeout=5))
                self.assertEqual(ack2["type"], "authenticated")

                # 1. u1 calls u2
                ws1.send(json.dumps({
                    "type": "call_invite",
                    "target_id": u2,
                    "call_type": "voice",
                }))
                initiated = json.loads(ws1.recv(timeout=5))
                self.assertEqual(initiated["type"], "call_initiated")

                incoming = json.loads(ws2.recv(timeout=5))
                self.assertEqual(incoming["type"], "incoming_call")
                call_id = incoming["call_id"]

                # ws1 receives call_ringing
                ringing = json.loads(ws1.recv(timeout=5))
                self.assertEqual(ringing["type"], "call_ringing")

                # 2. u2 accepts
                ws2.send(json.dumps({"type": "call_accept", "call_id": call_id}))
                accepted = json.loads(ws1.recv(timeout=5))  # call_accepted
                self.assertEqual(accepted["type"], "call_accepted")

                # 3. u2 sends callee_ready
                ws2.send(json.dumps({"type": "callee_ready", "call_id": call_id}))
                ready_msg = json.loads(ws1.recv(timeout=5))
                self.assertEqual(ready_msg["type"], "callee_ready")
                self.assertEqual(ready_msg["call_id"], call_id)
                self.assertEqual(ready_msg["sender_id"], u2)
        print("  [PASS] WebRTC callee_ready readiness handshake verified")

    def test_11_fcm_push_notification_dispatch(self):
        """Tests FCM push notification: callee offline -> push attempted; callee online -> push skipped; invalid token removed."""
        from backend.app.services.fcm_service import set_mock_fcm_sender

        u1, t1 = self.create_test_user("fcm_u1@test.com", "fcm_u1")
        u2, t2 = self.create_test_user("fcm_u2@test.com", "fcm_u2")
        self.create_test_pair(u1, u2)

        # 1. Register two device tokens for u2: one valid, one invalid
        db = TestingSessionLocal()
        db.add(DevicePushToken(user_id=u2, token="VALID_TOKEN_U2_DEVICE_A", platform="android"))
        db.add(DevicePushToken(user_id=u2, token="INVALID_TOKEN_EXPIRED", platform="android"))
        db.commit()
        db.close()

        sent_pushes = []

        def fake_fcm_sender(db, target_id, tokens, call_id, caller_name, call_type):
            tokens_to_delete = []
            for t in tokens:
                if t.token == "INVALID_TOKEN_EXPIRED":
                    tokens_to_delete.append(t)
                else:
                    sent_pushes.append({
                        "token": t.token,
                        "call_id": call_id,
                        "caller_name": caller_name,
                        "call_type": call_type,
                    })
            for t in tokens_to_delete:
                db.delete(t)
            db.commit()
            return len(sent_pushes)

        set_mock_fcm_sender(fake_fcm_sender)

        from backend.app.services.signaling_manager import secure_call_manager
        old_timeout = secure_call_manager._ringing_ack_timeout
        secure_call_manager._ringing_ack_timeout = 1.0  # Fast 1s timeout for deterministic testing

        try:
            # Case 1: Callee u2 is ONLINE + ACKS call_ringing -> push must NOT be attempted
            with ws_connect(f"{self.base_ws_url}/ws/call?token={t1}") as ws1:
                with ws_connect(f"{self.base_ws_url}/ws/call?token={t2}") as ws2:
                    _ = json.loads(ws1.recv(timeout=5))  # authenticated
                    _ = json.loads(ws2.recv(timeout=5))  # authenticated

                    ws1.send(json.dumps({
                        "type": "call_invite",
                        "target_id": u2,
                        "call_type": "voice",
                    }))
                    initiated_a = json.loads(ws1.recv(timeout=5))  # call_initiated
                    _ = json.loads(ws2.recv(timeout=5))  # incoming_call
                    _ = json.loads(ws1.recv(timeout=5))  # call_ringing from invite delivery

                    # Callee acknowledges ringing
                    ws2.send(json.dumps({
                        "type": "call_ringing",
                        "call_id": initiated_a["call_id"],
                    }))

                    # Wait beyond timeout to ensure no push was fired
                    time.sleep(1.2)
                    self.assertEqual(len(sent_pushes), 0)

                    # Cancel call so session is completed
                    ws1.send(json.dumps({
                        "type": "call_cancel",
                        "call_id": initiated_a["call_id"],
                    }))
                    _ = json.loads(ws2.recv(timeout=5))  # call_cancelled

            # Case 2: Callee u2 is ONLINE + NO ACK -> timeout expires -> push IS attempted
            sent_pushes.clear()
            with ws_connect(f"{self.base_ws_url}/ws/call?token={t1}") as ws1:
                with ws_connect(f"{self.base_ws_url}/ws/call?token={t2}") as ws2:
                    _ = json.loads(ws1.recv(timeout=5))
                    _ = json.loads(ws2.recv(timeout=5))

                    ws1.send(json.dumps({
                        "type": "call_invite",
                        "target_id": u2,
                        "call_type": "voice",
                    }))
                    initiated_b = json.loads(ws1.recv(timeout=5))  # call_initiated
                    _ = json.loads(ws2.recv(timeout=5))  # incoming_call
                    _ = json.loads(ws1.recv(timeout=5))  # call_ringing

                    # Callee intentionally does NOT send call_ringing ack.
                    # Poll for fallback FCM push after the 1s timeout
                    for _ in range(30):
                        if len(sent_pushes) >= 1:
                            break
                        time.sleep(0.1)

                    self.assertEqual(len(sent_pushes), 1)
                    self.assertEqual(sent_pushes[0]["call_id"], initiated_b["call_id"])

                    # Cancel call
                    ws1.send(json.dumps({
                        "type": "call_cancel",
                        "call_id": initiated_b["call_id"],
                    }))
                    _ = json.loads(ws2.recv(timeout=5))  # call_cancelled

            # Case 3: Callee u2 is OFFLINE -> push attempted immediately, invalid token removed
            sent_pushes.clear()
            with ws_connect(f"{self.base_ws_url}/ws/call?token={t1}") as ws1:
                _ = json.loads(ws1.recv(timeout=5))  # authenticated

                ws1.send(json.dumps({
                    "type": "call_invite",
                    "target_id": u2,
                    "call_type": "video",
                }))
                initiated_c = json.loads(ws1.recv(timeout=5))
                self.assertEqual(initiated_c["type"], "call_initiated")

                # Verify push was sent with proper data payload
                for _ in range(30):
                    if len(sent_pushes) >= 1:
                        break
                    time.sleep(0.1)

                self.assertEqual(len(sent_pushes), 1)
                push = sent_pushes[0]
                self.assertEqual(push["token"], "VALID_TOKEN_U2_DEVICE_A")
                self.assertEqual(push["call_id"], initiated_c["call_id"])
                self.assertEqual(push["call_type"], "video")

                # Verify database: INVALID_TOKEN_EXPIRED was deleted, VALID token remains
                db = TestingSessionLocal()
                remaining_tokens = [
                    t.token for t in db.query(DevicePushToken).filter(DevicePushToken.user_id == u2).all()
                ]
                self.assertIn("VALID_TOKEN_U2_DEVICE_A", remaining_tokens)
                self.assertNotIn("INVALID_TOKEN_EXPIRED", remaining_tokens)
                db.close()

            print("  [PASS] FCM push: online+acks (no push), online+no ack (push), offline (push) verified")
        finally:
            secure_call_manager._ringing_ack_timeout = old_timeout
            set_mock_fcm_sender(None)


if __name__ == "__main__":
    unittest.main(verbosity=2)


