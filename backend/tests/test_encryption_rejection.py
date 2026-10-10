import io
import os
import unittest
from datetime import datetime, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app, get_db
from app.core.database import Base
from app.models.user import User
from app.models.couple import Pair
from app.models.message import Message
from app.models.media import Media
from app.core.security import hash_password, create_access_token

TEST_DB_PATH = "./test_encryption_rejection.db"
SQLALCHEMY_DATABASE_URL = f"sqlite:///{TEST_DB_PATH}"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


client = TestClient(app)


class EncryptionRejectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.path.exists(TEST_DB_PATH):
            try:
                os.remove(TEST_DB_PATH)
            except Exception:
                pass
        Base.metadata.create_all(bind=engine)
        app.dependency_overrides[get_db] = override_get_db

        db = TestingSessionLocal()
        u1 = User(
            email="enc_alice@twoofus.app",
            username="enc_alice",
            password_hash=hash_password("Secret123!"),
            public_key="alice_public_key_base64_example==",
        )
        u2 = User(
            email="enc_bob@twoofus.app",
            username="enc_bob",
            password_hash=hash_password("Secret123!"),
            public_key="bob_public_key_base64_example==",
        )
        db.add_all([u1, u2])
        db.commit()
        db.refresh(u1)
        db.refresh(u2)

        cls.u1_id = u1.id
        cls.u2_id = u2.id

        pair = Pair(user1_id=u1.id, user2_id=u2.id)
        db.add(pair)
        db.commit()
        db.refresh(pair)
        cls.pair_id = pair.id
        db.close()

        cls.t1 = create_access_token(data={"sub": str(cls.u1_id)})
        cls.t2 = create_access_token(data={"sub": str(cls.u2_id)})
        cls.headers_u1 = {"Authorization": f"Bearer {cls.t1}"}
        cls.headers_u2 = {"Authorization": f"Bearer {cls.t2}"}

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=engine)
        if os.path.exists(TEST_DB_PATH):
            try:
                os.remove(TEST_DB_PATH)
            except Exception:
                pass

    def test_01_encrypted_message_requires_valid_nonce(self):
        # Missing nonce
        res1 = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "encrypted_ciphertext_payload",
                "is_encrypted": True,
                "nonce": None,
            },
            headers=self.headers_u1,
        )
        self.assertEqual(res1.status_code, 400)
        self.assertIn("valid encryption nonce", res1.json()["detail"])

        # Whitespace-only nonce
        res2 = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "encrypted_ciphertext_payload",
                "is_encrypted": True,
                "nonce": "   ",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(res2.status_code, 400)
        self.assertIn("valid encryption nonce", res2.json()["detail"])

    def test_02_encrypted_message_requires_ciphertext_content(self):
        res = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "   ",
                "is_encrypted": True,
                "nonce": "validNonceBase64==",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("ciphertext content", res.json()["detail"])

    def test_03_protected_message_type_rejects_unencrypted_payload(self):
        res = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "plaintext message claiming encrypted type",
                "is_encrypted": False,
                "message_type": "encrypted_text",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Payload must be encrypted", res.json()["detail"])

    def test_04_encrypted_message_edit_requires_valid_nonce_and_content(self):
        send_res = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "encrypted_ciphertext_init",
                "is_encrypted": True,
                "nonce": "initNonce==",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(send_res.status_code, 200)
        msg_id = send_res.json()["message_id"]

        # Edit with missing nonce
        edit_res1 = client.put(
            f"/messages/{msg_id}",
            json={
                "content": "new_ciphertext",
                "is_encrypted": True,
                "nonce": "",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(edit_res1.status_code, 400)
        self.assertIn("valid encryption nonce", edit_res1.json()["detail"])

        # Edit with missing ciphertext
        edit_res2 = client.put(
            f"/messages/{msg_id}",
            json={
                "content": "   ",
                "is_encrypted": True,
                "nonce": "validNonce==",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(edit_res2.status_code, 400)
        self.assertIn("ciphertext content", edit_res2.json()["detail"])

    def test_05_view_once_media_rejects_unencrypted(self):
        fake_bytes = b"FAKE_PHOTO_DATA_VIEW_ONCE"
        res = client.post(
            "/media/upload",
            data={
                "receiver_id": str(self.u2_id),
                "is_view_once": "true",
                "is_encrypted": "false",
            },
            files=[("files", ("photo.jpg", io.BytesIO(fake_bytes), "image/jpeg"))],
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("must be end-to-end encrypted", res.json()["detail"])

    def test_06_unencrypted_media_cannot_have_keys_or_nonces(self):
        fake_bytes = b"FAKE_PHOTO_DATA"
        res = client.post(
            "/media/upload",
            data={
                "receiver_id": str(self.u2_id),
                "is_encrypted": "false",
                "encrypted_media_key": "inconsistent_key",
                "encryption_nonce": "inconsistent_nonce",
            },
            files=[("files", ("photo.jpg", io.BytesIO(fake_bytes), "image/jpeg"))],
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Unencrypted media cannot contain encryption keys", res.json()["detail"])

    def test_07_encrypted_media_rejects_empty_key_or_nonce(self):
        fake_bytes = b"FAKE_ENCRYPTED_PHOTO"
        res = client.post(
            "/media/upload",
            data={
                "receiver_id": str(self.u2_id),
                "is_encrypted": "true",
                "encrypted_media_key": "   ",
                "encryption_nonce": "valid_nonce",
            },
            files=[("files", ("photo.jpg", io.BytesIO(fake_bytes), "image/jpeg"))],
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("cannot have empty encrypted_media_key", res.json()["detail"])

    def test_08_message_edit_cannot_downgrade_encryption(self):
        # Create an encrypted message
        send_res = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "encrypted_ciphertext_init",
                "is_encrypted": True,
                "nonce": "initNonce==",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(send_res.status_code, 200)
        msg_id = send_res.json()["message_id"]

        # Attempt to downgrade to plaintext
        edit_res = client.put(
            f"/messages/{msg_id}",
            json={
                "content": "plaintext downgraded content",
                "is_encrypted": False,
            },
            headers=self.headers_u1,
        )
        self.assertEqual(edit_res.status_code, 400)
        self.assertIn("Cannot downgrade an encrypted message to plaintext", edit_res.json()["detail"])

    def test_09_valid_encrypted_message_succeeds(self):
        res = client.post(
            "/send-message",
            json={
                "sender_id": self.u1_id,
                "receiver_id": self.u2_id,
                "content": "validCiphertextBase64==",
                "is_encrypted": True,
                "nonce": "validNonceBase64==",
                "message_type": "encrypted_text",
            },
            headers=self.headers_u1,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "sent")
