import io
import os
import sys
import uuid
import pytest
from fastapi.testclient import TestClient

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

from backend.app.main import app
from backend.app.core.database import SessionLocal
from backend.app.models.user import User
from backend.app.models.couple import Pair

client = TestClient(app)

class TestMediaRoundtrip:
    @classmethod
    def setup_class(cls):
        suffix = uuid.uuid4().hex[:8]
        cls.user_a_email = f"alice_{suffix}@test.com"
        cls.user_a_name = f"alice_{suffix}"
        cls.user_b_email = f"bob_{suffix}@test.com"
        cls.user_b_name = f"bob_{suffix}"
        cls.user_c_email = f"charlie_{suffix}@test.com"
        cls.user_c_name = f"charlie_{suffix}"
        cls.password = "SecurePassword123!"

        # Register User A
        r_a = client.post("/register", json={"email": cls.user_a_email, "username": cls.user_a_name, "password": cls.password})
        assert r_a.status_code == 200
        cls.user_a_id = r_a.json()["user_id"]

        # Register User B
        r_b = client.post("/register", json={"email": cls.user_b_email, "username": cls.user_b_name, "password": cls.password})
        assert r_b.status_code == 200
        cls.user_b_id = r_b.json()["user_id"]

        # Register User C (attacker/unpaired)
        r_c = client.post("/register", json={"email": cls.user_c_email, "username": cls.user_c_name, "password": cls.password})
        assert r_c.status_code == 200
        cls.user_c_id = r_c.json()["user_id"]

        # Login User A
        l_a = client.post("/login", json={"email": cls.user_a_email, "password": cls.password})
        assert l_a.status_code == 200
        cls.token_a = l_a.json()["access_token"]

        # Login User B
        l_b = client.post("/login", json={"email": cls.user_b_email, "password": cls.password})
        assert l_b.status_code == 200
        cls.token_b = l_b.json()["access_token"]

        # Login User C
        l_c = client.post("/login", json={"email": cls.user_c_email, "password": cls.password})
        assert l_c.status_code == 200
        cls.token_c = l_c.json()["access_token"]

        # Pair User A and User B in DB
        db = SessionLocal()
        try:
            pair = Pair(user1_id=cls.user_a_id, user2_id=cls.user_b_id)
            db.add(pair)
            db.commit()
            db.refresh(pair)
            cls.pair_id = pair.id
        finally:
            db.close()

    def test_01_upload_encrypted_media_roundtrip(self):
        sample_ciphertext = b"\x01\x02\x03\x04\x05ENCRYPTED_IMAGE_PAYLOAD_TEST_BYTES\x06\x07\x08"
        file_tuple = ("files", ("enc_test_photo.png", io.BytesIO(sample_ciphertext), "image/png"))

        form_data = {
            "receiver_id": str(self.user_b_id),
            "is_encrypted": "true",
            "is_view_once": "false",
            "encrypted_media_key": '{"k":"mockKeyBundleBase64","n":"mockKeyNonce"}',
            "encryption_nonce": "mockFileNonceBase64",
        }

        # User A uploads media
        res = client.post(
            "/media/upload",
            data=form_data,
            files=[file_tuple],
            headers={"Authorization": f"Bearer {self.token_a}"}
        )
        assert res.status_code == 200, f"Upload failed: {res.text}"
        data = res.json()
        assert len(data) == 1
        TestMediaRoundtrip.uploaded_media_id = data[0]["media_id"]
        assert data[0]["media_id"] > 0

    def test_02_receiver_fetches_file_bytes(self):
        # User B (receiver) downloads the encrypted file
        res = client.get(
            f"/media/{self.uploaded_media_id}/file",
            headers={"Authorization": f"Bearer {self.token_b}"}
        )
        assert res.status_code == 200
        sample_ciphertext = b"\x01\x02\x03\x04\x05ENCRYPTED_IMAGE_PAYLOAD_TEST_BYTES\x06\x07\x08"
        assert res.content == sample_ciphertext

    def test_03_receiver_fetches_thumbnail_fallback(self):
        # User B requests thumbnail for encrypted image.
        # Since server-side thumbnailing is skipped for zero-knowledge ciphertext,
        # it must safely fallback to serving the storage payload.
        res = client.get(
            f"/media/{self.uploaded_media_id}/thumbnail",
            headers={"Authorization": f"Bearer {self.token_b}"}
        )
        assert res.status_code == 200
        sample_ciphertext = b"\x01\x02\x03\x04\x05ENCRYPTED_IMAGE_PAYLOAD_TEST_BYTES\x06\x07\x08"
        assert res.content == sample_ciphertext

    def test_04_receiver_gallery_metadata_preserves_e2ee_keys(self):
        # User B retrieves the pair media gallery
        res = client.get(
            f"/media/pair/{self.user_a_id}",
            headers={"Authorization": f"Bearer {self.token_b}"}
        )
        assert res.status_code == 200
        items = res.json()
        assert len(items) >= 1
        matched = next((m for m in items if m["id"] == self.uploaded_media_id), None)
        assert matched is not None
        assert matched["is_encrypted"] is True
        assert matched["encrypted_media_key"] == '{"k":"mockKeyBundleBase64","n":"mockKeyNonce"}'
        assert matched["encryption_nonce"] == "mockFileNonceBase64"

    def test_05_unauthorized_user_cannot_access_media(self):
        # User C (unrelated third party) tries to access User A's media
        res_file = client.get(
            f"/media/{self.uploaded_media_id}/file",
            headers={"Authorization": f"Bearer {self.token_c}"}
        )
        assert res_file.status_code == 403

        res_thumb = client.get(
            f"/media/{self.uploaded_media_id}/thumbnail",
            headers={"Authorization": f"Bearer {self.token_c}"}
        )
        assert res_thumb.status_code == 403
