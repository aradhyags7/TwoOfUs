import io
import os
import unittest
from datetime import datetime, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app, get_db
from app.core.database import Base
from app.core.security import hash_password, create_access_token
from app.models.user import User
from app.models.couple import Pair
from app.models.media import Media
from app.services.storage import (
    LocalStorage,
    S3Storage,
    _create_storage_backend,
    validate_file,
    storage_backend,
)


class FakeStreamingBody:
    def __init__(self, data: bytes):
        self._data = data
        self._stream = io.BytesIO(data)

    def read(self):
        return self._data

    def iter_chunks(self, chunk_size=64 * 1024):
        while True:
            chunk = self._stream.read(chunk_size)
            if not chunk:
                break
            yield chunk

    def close(self):
        pass


class FakeS3Client:
    def __init__(self):
        self.objects = {}

    def put_object(self, Bucket, Key, Body, ContentType="application/octet-stream"):
        if hasattr(Body, "read"):
            data = Body.read()
        elif isinstance(Body, bytes):
            data = Body
        else:
            data = str(Body).encode("utf-8")
        self.objects[(Bucket, Key)] = {
            "body": data,
            "content_type": ContentType,
            "length": len(data),
        }
        return {"ResponseMetadata": {"HTTPStatusCode": 200}}

    def get_object(self, Bucket, Key):
        if (Bucket, Key) not in self.objects:
            from botocore.exceptions import ClientError
            raise ClientError({"Error": {"Code": "NoSuchKey", "Message": "Key not found"}}, "GetObject")
        item = self.objects[(Bucket, Key)]
        return {
            "Body": FakeStreamingBody(item["body"]),
            "ContentType": item["content_type"],
            "ContentLength": item["length"],
        }

    def head_object(self, Bucket, Key):
        if (Bucket, Key) not in self.objects:
            from botocore.exceptions import ClientError
            raise ClientError({"Error": {"Code": "404", "Message": "Not found"}}, "HeadObject")
        item = self.objects[(Bucket, Key)]
        return {
            "ContentType": item["content_type"],
            "ContentLength": item["length"],
        }

    def delete_object(self, Bucket, Key):
        self.objects.pop((Bucket, Key), None)
        return {"ResponseMetadata": {"HTTPStatusCode": 204}}

    def head_bucket(self, Bucket):
        return {"ResponseMetadata": {"HTTPStatusCode": 200}}

    def list_objects_v2(self, Bucket, MaxKeys=1):
        return {"KeyCount": len(self.objects)}


TEST_DB_PATH = "./test_storage_s3.db"
SQLALCHEMY_DATABASE_URL = f"sqlite:///{TEST_DB_PATH}"

test_engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


class StorageAbstractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=test_engine)
        db = TestingSessionLocal()

        db.query(Media).delete()
        db.query(Pair).delete()
        db.query(User).delete()
        db.commit()

        cls.user1 = User(
            username="s3_user1",
            email="s3_user1@example.com",
            password_hash=hash_password("Pass123!"),
        )
        cls.user2 = User(
            username="s3_user2",
            email="s3_user2@example.com",
            password_hash=hash_password("Pass123!"),
        )
        cls.user3 = User(
            username="s3_user3",
            email="s3_user3@example.com",
            password_hash=hash_password("Pass123!"),
        )
        db.add_all([cls.user1, cls.user2, cls.user3])
        db.commit()
        db.refresh(cls.user1)
        db.refresh(cls.user2)
        db.refresh(cls.user3)

        cls.u1_id = cls.user1.id
        cls.u2_id = cls.user2.id
        cls.u3_id = cls.user3.id

        cls.pair = Pair(
            user1_id=cls.u1_id,
            user2_id=cls.u2_id,
            connection_pin="S3PAIR",
        )
        db.add(cls.pair)
        db.commit()

        cls.token_u1 = create_access_token({"sub": str(cls.u1_id)})
        cls.token_u2 = create_access_token({"sub": str(cls.u2_id)})
        cls.token_u3 = create_access_token({"sub": str(cls.u3_id)})

        cls.headers_u1 = {"Authorization": f"Bearer {cls.token_u1}"}
        cls.headers_u2 = {"Authorization": f"Bearer {cls.token_u2}"}
        cls.headers_u3 = {"Authorization": f"Bearer {cls.token_u3}"}
        db.close()

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=test_engine)
        test_engine.dispose()
        if os.path.exists(TEST_DB_PATH):
            try:
                os.remove(TEST_DB_PATH)
            except Exception:
                pass

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db

    def test_01_s3_storage_unit_roundtrip_and_delete(self):
        fake_client = FakeS3Client()
        s3 = S3Storage(
            endpoint_url="https://fake.r2.cloudflarestorage.com",
            bucket="twoofus-test",
            access_key_id="fake_key",
            secret_access_key="fake_secret",
            region_name="auto",
            client=fake_client,
        )

        # Put
        test_key = "media/images/test_image.jpg"
        test_data = b"BINARY_IMAGE_DATA_12345"
        saved_key = s3.put(test_key, test_data, content_type="image/jpeg")
        self.assertEqual(saved_key, test_key)

        # Exists
        self.assertTrue(s3.exists(test_key))
        self.assertTrue(s3.exists(f"uploads/{test_key}"))

        # Get stream
        stream_tuple = s3.get_stream(test_key)
        self.assertIsNotNone(stream_tuple)
        stream_iter, c_type, c_len = stream_tuple
        retrieved_data = b"".join(stream_iter)
        self.assertEqual(retrieved_data, test_data)
        self.assertEqual(c_len, len(test_data))
        self.assertEqual(c_type, "image/jpeg")

        # Health
        self.assertEqual(s3.check_health(), "ok")

        # Delete
        del_res = s3.delete(test_key)
        self.assertTrue(del_res)
        self.assertFalse(s3.exists(test_key))
        self.assertIsNone(s3.get_stream(test_key))

    def test_02_s3_incomplete_config_falls_back_to_local_with_warning(self):
        old_backend = os.environ.get("STORAGE_BACKEND")
        os.environ["STORAGE_BACKEND"] = "s3"
        # Omit S3_ENDPOINT_URL, S3_BUCKET, etc.
        os.environ.pop("S3_ENDPOINT_URL", None)
        os.environ.pop("S3_BUCKET", None)

        backend = _create_storage_backend()
        self.assertIsInstance(backend, LocalStorage)
        self.assertEqual(backend.check_health(), "local")

        # Restore
        if old_backend:
            os.environ["STORAGE_BACKEND"] = old_backend
        else:
            os.environ.pop("STORAGE_BACKEND", None)

    def test_03_health_endpoint_reports_db_and_storage(self):
        res = client.get("/health")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["status"], "ok")
        self.assertIn("db", data)
        self.assertIn(data["db"], ["ok", "error"])
        self.assertIn("storage", data)
        self.assertIn(data["storage"], ["ok", "error", "local"])

    def test_04_api_upload_download_roundtrip_with_s3_backend(self):
        # Inject FakeS3Client into global storage_backend
        fake_client = FakeS3Client()
        s3 = S3Storage(
            endpoint_url="https://fake.r2.cloudflarestorage.com",
            bucket="twoofus-test",
            access_key_id="fake_key",
            secret_access_key="fake_secret",
            region_name="auto",
            client=fake_client,
        )

        import app.services.storage as storage_mod
        import app.main as main_mod
        orig_backend = storage_mod.storage_backend
        storage_mod.set_storage_backend(s3)
        main_mod.storage_backend = s3

        try:
            payload = b"ENCRYPTED_MEDIA_BLOB_FOR_ROUNDTRIP"
            upload_res = client.post(
                "/media/upload",
                data={
                    "receiver_id": str(self.u2_id),
                    "is_encrypted": "true",
                    "encrypted_media_key": "validEncKey==",
                    "encryption_nonce": "validNonce==",
                },
                files=[("files", ("secure_photo.jpg", io.BytesIO(payload), "image/jpeg"))],
                headers=self.headers_u1,
            )
            self.assertEqual(upload_res.status_code, 200)
            media_item = upload_res.json()[0]
            media_id = media_item["media_id"]

            # Download as partner
            dl_res = client.get(
                f"/media/{media_id}/file",
                headers=self.headers_u2,
            )
            self.assertEqual(dl_res.status_code, 200)
            self.assertEqual(dl_res.content, payload)

            # Delete media
            del_res = client.delete(
                f"/media/{media_id}",
                headers=self.headers_u1,
            )
            self.assertEqual(del_res.status_code, 200)

            # Object must be deleted from S3
            storage_path = media_item["storage_path"]
            self.assertFalse(s3.exists(storage_path))
        finally:
            storage_mod.set_storage_backend(orig_backend)
            main_mod.storage_backend = orig_backend

    def test_05_api_view_once_shreds_object_from_s3(self):
        fake_client = FakeS3Client()
        s3 = S3Storage(
            endpoint_url="https://fake.r2.cloudflarestorage.com",
            bucket="twoofus-test",
            access_key_id="fake_key",
            secret_access_key="fake_secret",
            region_name="auto",
            client=fake_client,
        )

        import app.services.storage as storage_mod
        import app.main as main_mod
        orig_backend = storage_mod.storage_backend
        storage_mod.set_storage_backend(s3)
        main_mod.storage_backend = s3

        try:
            payload = b"VIEW_ONCE_ENCRYPTED_SECRET"
            upload_res = client.post(
                "/media/upload",
                data={
                    "receiver_id": str(self.u2_id),
                    "is_encrypted": "true",
                    "is_view_once": "true",
                    "encrypted_media_key": "viewOnceKey==",
                    "encryption_nonce": "viewOnceNonce==",
                },
                files=[("files", ("secret.jpg", io.BytesIO(payload), "image/jpeg"))],
                headers=self.headers_u1,
            )
            self.assertEqual(upload_res.status_code, 200)
            media_item = upload_res.json()[0]
            media_id = media_item["media_id"]
            storage_path = media_item["storage_path"]

            # Verify it exists in S3 before consumption
            self.assertTrue(s3.exists(storage_path))

            # Consume view-once as receiver
            view_res = client.get(
                f"/media/{media_id}/file",
                headers=self.headers_u2,
            )
            self.assertEqual(view_res.status_code, 200)
            self.assertEqual(view_res.content, payload)
            self.assertEqual(view_res.headers.get("X-View-Once-Consumed"), "true")

            # Verify object is immediately SHREDDED from S3 bucket!
            self.assertFalse(s3.exists(storage_path))

            # Subsequent attempt to view returns 410 Gone
            second_view = client.get(
                f"/media/{media_id}/file",
                headers=self.headers_u2,
            )
            self.assertEqual(second_view.status_code, 410)
        finally:
            storage_mod.set_storage_backend(orig_backend)
            main_mod.storage_backend = orig_backend

    def test_06_unauthorized_user_gets_403(self):
        fake_client = FakeS3Client()
        s3 = S3Storage(
            endpoint_url="https://fake.r2.cloudflarestorage.com",
            bucket="twoofus-test",
            access_key_id="fake_key",
            secret_access_key="fake_secret",
            region_name="auto",
            client=fake_client,
        )

        import app.services.storage as storage_mod
        import app.main as main_mod
        orig_backend = storage_mod.storage_backend
        storage_mod.set_storage_backend(s3)
        main_mod.storage_backend = s3

        try:
            payload = b"SECRET_FOR_PAIR_ONLY"
            upload_res = client.post(
                "/media/upload",
                data={
                    "receiver_id": str(self.u2_id),
                    "is_encrypted": "true",
                    "encrypted_media_key": "privKey==",
                    "encryption_nonce": "privNonce==",
                },
                files=[("files", ("private.jpg", io.BytesIO(payload), "image/jpeg"))],
                headers=self.headers_u1,
            )
            self.assertEqual(upload_res.status_code, 200)
            media_id = upload_res.json()[0]["media_id"]

            # User 3 (unpaired eavesdropper) attempts to download
            forbidden_res = client.get(
                f"/media/{media_id}/file",
                headers=self.headers_u3,
            )
            self.assertEqual(forbidden_res.status_code, 403)
        finally:
            storage_mod.set_storage_backend(orig_backend)
            main_mod.storage_backend = orig_backend

    def test_07_missing_object_returns_404_no_crash(self):
        # Request non-existent upload path
        res = client.get("/uploads/media/images/nonexistent_file_12345.jpg")
        self.assertEqual(res.status_code, 404)
        self.assertIn("File no longer available", res.json()["detail"])

    def test_08_blocked_extension_and_size_limits_enforced(self):
        from fastapi import HTTPException
        fake_upload = type("MockFile", (), {
            "filename": "malicious.exe",
            "content_type": "application/x-msdownload",
        })()
        with self.assertRaises(HTTPException) as ctx:
            validate_file(fake_upload, 1024)
        self.assertEqual(ctx.exception.status_code, 415)

        # Huge file
        huge_file = type("MockFile", (), {
            "filename": "huge.jpg",
            "content_type": "image/jpeg",
        })()
        with self.assertRaises(HTTPException) as ctx2:
            validate_file(huge_file, 200 * 1024 * 1024)
        self.assertEqual(ctx2.exception.status_code, 413)


if __name__ == "__main__":
    unittest.main()
