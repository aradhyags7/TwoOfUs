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

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db

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
        uid: int = getattr(user, "id")
        token = create_access_token({"sub": str(uid), "email": email})
        db.close()
        return uid, token

    def create_test_pair(self, u1: int, u2: int) -> int:
        db = TestingSessionLocal()
        pair = Pair(user1_id=u1, user2_id=u2, connection_pin=f"PIN_{uuid.uuid4().hex[:8]}")
        db.add(pair)
        db.commit()
        db.refresh(pair)
        pid: int = getattr(pair, "id")
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

    def test_06_message_deletion_cleans_db_and_disk(self):
        u1, t1 = self.create_test_user("del_u1@twoofus.app", "del_u1")
        u2, t2 = self.create_test_user("del_u2@twoofus.app", "del_u2")
        self.create_test_pair(u1, u2)

        headers_u1 = {"Authorization": f"Bearer {t1}"}
        headers_u2 = {"Authorization": f"Bearer {t2}"}

        # Upload a photo attached to message
        raw_ciphertext = b"TEST_PAYLOAD_FOR_MESSAGE_DELETION"
        upload_res = client.post(
            "/media/upload",
            data={"receiver_id": str(u2), "is_encrypted": "true"},
            files=[("files", ("test.jpg", io.BytesIO(raw_ciphertext), "image/jpeg"))],
            headers=headers_u1
        )
        self.assertEqual(upload_res.status_code, 200)
        media_id = upload_res.json()[0]["media_id"]

        # Send message with media
        send_res = client.post(
            "/send-message",
            json={"sender_id": u1, "receiver_id": u2, "content": "hi with attachment", "media_ids": [media_id]},
            headers=headers_u1
        )
        self.assertEqual(send_res.status_code, 200)
        msg_id = send_res.json()["message_id"]

        # Verify exists in db and disk
        db = TestingSessionLocal()
        msg_rec = db.query(Message).filter(Message.id == msg_id).first()
        media_rec = db.query(Media).filter(Media.id == media_id).first()
        self.assertIsNotNone(msg_rec)
        self.assertIsNotNone(media_rec)
        storage_path = str(getattr(media_rec, "storage_path", ""))
        self.assertTrue(os.path.exists(storage_path))
        db.close()

        # Receiver deletes message -> should succeed and delete from DB & disk
        del_res = client.delete(f"/messages/{msg_id}", headers=headers_u2)
        self.assertEqual(del_res.status_code, 200)

        # Verify completely gone from DB and disk
        db = TestingSessionLocal()
        self.assertIsNone(db.query(Message).filter(Message.id == msg_id).first())
        self.assertIsNone(db.query(Media).filter(Media.id == media_id).first())
        self.assertFalse(os.path.exists(storage_path))
        db.close()
        print("  [PASS] Message deletion completely wipes message, media record, and physical disk file")

    def test_07_clear_conversation_wipes_all(self):
        u1, t1 = self.create_test_user("clear_u1@twoofus.app", "clear_u1")
        u2, t2 = self.create_test_user("clear_u2@twoofus.app", "clear_u2")
        self.create_test_pair(u1, u2)

        headers_u1 = {"Authorization": f"Bearer {t1}"}

        # Send 3 messages
        client.post("/send-message", json={"sender_id": u1, "receiver_id": u2, "content": "msg 1"}, headers=headers_u1)
        client.post("/send-message", json={"sender_id": u1, "receiver_id": u2, "content": "msg 2"}, headers=headers_u1)
        client.post("/send-message", json={"sender_id": u1, "receiver_id": u2, "content": "msg 3"}, headers=headers_u1)

        # Clear conversation
        clear_res = client.delete(f"/messages/conversation/{u2}", headers=headers_u1)
        self.assertEqual(clear_res.status_code, 200)
        self.assertEqual(clear_res.json()["deleted_count"], 3)

        # Verify 0 messages left
        msg_res = client.get(f"/messages/{u1}/{u2}", headers=headers_u1)
        self.assertEqual(len(msg_res.json()), 0)
        print("  [PASS] Clear conversation completely purges all conversation history from DB")

    def test_08_forgot_and_reset_password_lifecycle(self):
        u1, t1 = self.create_test_user("forgot_u1@twoofus.app", "forgot_u1", "OldSecretPassword123!")

        # 1. Non-existent account returns 404
        bad_req = client.post("/forgot-password", json={"email_or_username": "non_existent@twoofus.app"})
        self.assertEqual(bad_req.status_code, 404)

        # 2. Request OTP with email
        req_res = client.post("/forgot-password", json={"email_or_username": "forgot_u1@twoofus.app"})
        self.assertEqual(req_res.status_code, 200)
        
        db = TestingSessionLocal()
        user_db = db.query(User).filter(User.email == "forgot_u1@twoofus.app").first()
        self.assertIsNotNone(user_db)
        reset_code = str(user_db.reset_otp)
        db.close()
        self.assertEqual(len(reset_code), 6)

        # 3. Wrong reset code returns 400
        bad_code_res = client.post(
            "/reset-password",
            json={"email_or_username": "forgot_u1", "reset_code": "000000", "new_password": "NewSecretPassword123!"}
        )
        self.assertEqual(bad_code_res.status_code, 400)

        # 4. Short password returns 400
        short_res = client.post(
            "/reset-password",
            json={"email_or_username": "forgot_u1", "reset_code": reset_code, "new_password": "123"}
        )
        self.assertEqual(short_res.status_code, 400)

        # 5. Correct reset code and valid new password
        success_res = client.post(
            "/reset-password",
            json={"email_or_username": "forgot_u1", "reset_code": reset_code, "new_password": "NewSecretPassword123!"}
        )
        self.assertEqual(success_res.status_code, 200)

        # 6. Verify old password fails and new password succeeds on /login
        old_login = client.post("/login", json={"email": "forgot_u1@twoofus.app", "password": "OldSecretPassword123!"})
        self.assertEqual(old_login.status_code, 401)

        new_login = client.post("/login", json={"email": "forgot_u1@twoofus.app", "password": "NewSecretPassword123!"})
        self.assertEqual(new_login.status_code, 200)
        self.assertIn("access_token", new_login.json())
        print("  [PASS] Forgot & Reset Password lifecycle: OTP generation, validation, password replacement, and post-reset login verified")

    def test_09_user_enumeration_and_pair_privacy_restriction(self):
        u1, t1 = self.create_test_user("enum_u1@test.com", "enum_u1")
        u2, t2 = self.create_test_user("enum_u2@test.com", "enum_u2")
        stranger, str_token = self.create_test_user("stranger@test.com", "stranger")

        self.create_test_pair(u1, u2)

        h1 = {"Authorization": f"Bearer {t1}"}
        h_stranger = {"Authorization": f"Bearer {str_token}"}

        # 1. GET /users as u1 should ONLY return u1 and u2, NOT stranger
        users_res = client.get("/users", headers=h1)
        self.assertEqual(users_res.status_code, 200)
        user_ids = [u["id"] for u in users_res.json()]
        self.assertIn(u1, user_ids)
        self.assertIn(u2, user_ids)
        self.assertNotIn(stranger, user_ids)

        # 2. GET /pairs as stranger should return empty list
        pairs_res = client.get("/pairs", headers=h_stranger)
        self.assertEqual(pairs_res.status_code, 200)
        self.assertEqual(len(pairs_res.json()), 0)
        print("  [PASS] Privacy restriction: User enumeration and cross-pair inspection completely blocked")

    def test_10_unpaired_media_upload_rejected(self):
        u1, t1 = self.create_test_user("unpaired_u1@test.com", "unpaired_u1")
        u2, t2 = self.create_test_user("unpaired_u2@test.com", "unpaired_u2")
        # Do NOT pair them

        h1 = {"Authorization": f"Bearer {t1}"}
        fake_image = io.BytesIO(b"\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xFF\xDB\x00C\x00" + b"\x00" * 200 + b"\xFF\xD9")

        res = client.post(
            "/media/upload",
            data={"receiver_id": str(u2)},
            files={"files": ("test.jpg", fake_image, "image/jpeg")},
            headers=h1
        )
        self.assertEqual(res.status_code, 403)
        print("  [PASS] Unpaired media upload rejected with HTTP 403 Forbidden")


if __name__ == "__main__":
    unittest.main(verbosity=2)

