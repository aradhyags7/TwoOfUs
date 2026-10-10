import io
import mimetypes
import os
import shutil
import uuid
from abc import ABC, abstractmethod
from typing import BinaryIO, Iterator, Optional, Tuple, Union
from fastapi import HTTPException, UploadFile

from ..core.config import settings

# Dangerous extensions explicitly prohibited
BLOCKED_EXTENSIONS = {
    ".exe", ".apk", ".bat", ".cmd", ".sh", ".ps1", ".js", ".py", ".php",
    ".dll", ".so", ".vbs", ".msi", ".jar", ".elf", ".com", ".scr", ".sys",
    ".drv", ".cpl", ".reg", ".pif", ".application", ".gadget"
}

ALLOWED_IMAGE_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif", "image/heic"
}

ALLOWED_VIDEO_TYPES = {
    "video/mp4", "video/webm", "video/quicktime", "video/x-matroska", "video/avi", "video/mpeg"
}

ALLOWED_DOCUMENT_TYPES = {
    "application/pdf", "text/plain", "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/zip", "application/x-zip-compressed", "application/octet-stream"
}

CHUNK_SIZE = 64 * 1024  # 64 KB streaming chunks


def _normalize_key(key: str) -> str:
    """Normalizes object keys by stripping redundant slashes and uploads/ prefixes."""
    k = key.replace("\\", "/").strip("/")
    if k.startswith("uploads/"):
        k = k[len("uploads/"):]
    return k


class StorageBackend(ABC):
    @abstractmethod
    def put(self, key: str, data: Union[bytes, BinaryIO], content_type: Optional[str] = None) -> str:
        """Stores object bytes or stream under the given key. Returns normalized key."""
        pass

    @abstractmethod
    def get_stream(self, key: str) -> Optional[Tuple[Iterator[bytes], Optional[str], Optional[int]]]:
        """Returns tuple of (chunk_iterator, content_type, content_length) or None if missing."""
        pass

    @abstractmethod
    def delete(self, key: str) -> bool:
        """Deletes object from storage. Returns True if deleted or already absent."""
        pass

    @abstractmethod
    def exists(self, key: str) -> bool:
        """Checks if object exists in storage."""
        pass

    @abstractmethod
    def check_health(self) -> str:
        """Reports storage health status: 'ok', 'error', or 'local'."""
        pass


class LocalStorage(StorageBackend):
    def __init__(self, base_dir: str = "uploads"):
        self.base_dir = base_dir
        os.makedirs(self.base_dir, exist_ok=True)

    def _to_path(self, key: str) -> str:
        norm = _normalize_key(key)
        return os.path.join(self.base_dir, norm)

    def put(self, key: str, data: Union[bytes, BinaryIO], content_type: Optional[str] = None) -> str:
        norm = _normalize_key(key)
        path = self._to_path(norm)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if isinstance(data, bytes):
            with open(path, "wb") as f:
                f.write(data)
        else:
            if hasattr(data, "seek"):
                try:
                    data.seek(0)
                except Exception:
                    pass
            with open(path, "wb") as f:
                shutil.copyfileobj(data, f)
        return norm

    def get_stream(self, key: str) -> Optional[Tuple[Iterator[bytes], Optional[str], Optional[int]]]:
        path = self._to_path(key)
        if not os.path.isfile(path):
            # Check direct path in case key was an absolute or legacy path
            if os.path.isfile(key):
                path = key
            else:
                return None

        file_size = os.path.getsize(path)
        content_type, _ = mimetypes.guess_type(path)

        def file_iterator() -> Iterator[bytes]:
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    yield chunk

        return file_iterator(), content_type or "application/octet-stream", file_size

    def delete(self, key: str) -> bool:
        path = self._to_path(key)
        deleted = False
        if os.path.isfile(path):
            try:
                os.remove(path)
                deleted = True
            except Exception:
                pass
        # Check direct path in case of legacy local path
        if os.path.isfile(key):
            try:
                os.remove(key)
                deleted = True
            except Exception:
                pass
        return deleted or not os.path.exists(path)

    def exists(self, key: str) -> bool:
        path = self._to_path(key)
        return os.path.isfile(path) or os.path.isfile(key)

    def check_health(self) -> str:
        return "local"


class S3Storage(StorageBackend):
    def __init__(
        self,
        endpoint_url: str,
        bucket: str,
        access_key_id: str,
        secret_access_key: str,
        region_name: str = "auto",
        client=None
    ):
        self.endpoint_url = endpoint_url
        self.bucket = bucket
        self.region_name = region_name or "auto"

        if client is not None:
            self.client = client
        else:
            import boto3
            from botocore.config import Config
            cfg = Config(
                signature_version="s3v4",
                retries={"max_attempts": 3, "mode": "standard"},
                connect_timeout=5,
                read_timeout=10,
            )
            self.client = boto3.client(
                "s3",
                endpoint_url=self.endpoint_url,
                aws_access_key_id=access_key_id,
                aws_secret_access_key=secret_access_key,
                region_name=self.region_name,
                config=cfg,
            )

    def put(self, key: str, data: Union[bytes, BinaryIO], content_type: Optional[str] = None) -> str:
        norm = _normalize_key(key)
        c_type = content_type or mimetypes.guess_type(norm)[0] or "application/octet-stream"

        if isinstance(data, bytes):
            body_bytes = data
        else:
            if hasattr(data, "seek"):
                try:
                    data.seek(0)
                except Exception:
                    pass
            body_bytes = data.read()

        self.client.put_object(
            Bucket=self.bucket,
            Key=norm,
            Body=body_bytes,
            ContentType=c_type,
        )
        return norm

    def get_stream(self, key: str) -> Optional[Tuple[Iterator[bytes], Optional[str], Optional[int]]]:
        norm = _normalize_key(key)
        try:
            resp = self.client.get_object(Bucket=self.bucket, Key=norm)
        except Exception:
            # Try alternate key format (with uploads/ prefix if legacy)
            try:
                resp = self.client.get_object(Bucket=self.bucket, Key=f"uploads/{norm}")
            except Exception:
                return None

        body = resp["Body"]
        c_type = resp.get("ContentType", "application/octet-stream")
        c_len = resp.get("ContentLength")

        def stream_iterator() -> Iterator[bytes]:
            try:
                for chunk in body.iter_chunks(chunk_size=CHUNK_SIZE):
                    yield chunk
            finally:
                body.close()

        return stream_iterator(), c_type, c_len

    def delete(self, key: str) -> bool:
        norm = _normalize_key(key)
        try:
            self.client.delete_object(Bucket=self.bucket, Key=norm)
            return True
        except Exception:
            return False

    def exists(self, key: str) -> bool:
        norm = _normalize_key(key)
        try:
            self.client.head_object(Bucket=self.bucket, Key=norm)
            return True
        except Exception:
            try:
                self.client.head_object(Bucket=self.bucket, Key=f"uploads/{norm}")
                return True
            except Exception:
                return False

    def check_health(self) -> str:
        try:
            self.client.head_bucket(Bucket=self.bucket)
            return "ok"
        except Exception:
            try:
                self.client.list_objects_v2(Bucket=self.bucket, MaxKeys=1)
                return "ok"
            except Exception:
                return "error"


def _create_storage_backend() -> StorageBackend:
    backend_type = (os.getenv("STORAGE_BACKEND") or "local").strip().lower()

    if backend_type == "s3":
        endpoint = os.getenv("S3_ENDPOINT_URL", "").strip()
        bucket = os.getenv("S3_BUCKET", "").strip()
        key_id = os.getenv("S3_ACCESS_KEY_ID", "").strip()
        secret = os.getenv("S3_SECRET_ACCESS_KEY", "").strip()
        region = os.getenv("S3_REGION", "auto").strip() or "auto"

        if not (endpoint and bucket and key_id and secret):
            print("\n" + "!" * 70)
            print(" [STORAGE CONFIGURATION WARNING] STORAGE_BACKEND is set to 's3', but")
            print(" one or more required S3 environment variables are missing:")
            print(f" S3_ENDPOINT_URL={'set' if endpoint else 'MISSING'}, S3_BUCKET={'set' if bucket else 'MISSING'},")
            print(f" S3_ACCESS_KEY_ID={'set' if key_id else 'MISSING'}, S3_SECRET_ACCESS_KEY={'set' if secret else 'MISSING'}")
            print(" Falling back to LocalStorage backend.")
            print(" WARNING: Local uploads on Render ephemeral containers will not persist!")
            print("!" * 70 + "\n")
            return LocalStorage()

        try:
            return S3Storage(
                endpoint_url=endpoint,
                bucket=bucket,
                access_key_id=key_id,
                secret_access_key=secret,
                region_name=region,
            )
        except Exception as e:
            print("\n" + "!" * 70)
            print(f" [STORAGE CONFIGURATION ERROR] Failed to initialize S3Storage: {e}")
            print(" Falling back to LocalStorage.")
            print("!" * 70 + "\n")
            return LocalStorage()

    return LocalStorage()


# Global storage instance
storage_backend: StorageBackend = _create_storage_backend()


def set_storage_backend(backend: StorageBackend):
    """Sets the active storage backend (useful for testing or dynamic config)."""
    global storage_backend
    storage_backend = backend


def get_storage_health() -> str:
    """Returns 'ok', 'error', or 'local' for /health endpoint."""
    return storage_backend.check_health()


def ensure_media_dirs():
    """Ensures local directories exist if LocalStorage is active."""
    if isinstance(storage_backend, LocalStorage):
        base = settings.MEDIA_DIR
        dirs = [
            os.path.join(base, "images"),
            os.path.join(base, "videos"),
            os.path.join(base, "files"),
            os.path.join(base, "thumbnails"),
            os.path.join("uploads", "avatars"),
            os.path.join("uploads", "memories"),
        ]
        for d in dirs:
            os.makedirs(d, exist_ok=True)


def validate_file(file: UploadFile, file_size: int) -> Tuple[str, str]:
    """
    Validates file extension, mime type, and file size.
    Returns tuple of (media_type, normalized_ext).
    """
    filename = file.filename or "attachment.bin"
    ext = os.path.splitext(filename)[1].lower()

    if ext in BLOCKED_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Executable or dangerous file type ({ext}) is strictly prohibited."
        )

    content_type = (file.content_type or "").lower()

    # Determine media category
    if content_type in ALLOWED_IMAGE_TYPES or ext in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic"}:
        media_type = "image"
        max_size = settings.MAX_IMAGE_SIZE_BYTES
    elif content_type in ALLOWED_VIDEO_TYPES or ext in {".mp4", ".webm", ".mov", ".mkv", ".avi"}:
        media_type = "video"
        max_size = settings.MAX_VIDEO_SIZE_BYTES
    else:
        media_type = "file"
        max_size = settings.MAX_FILE_SIZE_BYTES

    if file_size > max_size:
        max_mb = max_size // (1024 * 1024)
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds maximum allowed size of {max_mb} MB."
        )

    return media_type, ext if ext else ".bin"


def save_upload_file(
    file: UploadFile,
    media_type: str,
    ext: str,
    is_encrypted: bool = False
) -> Tuple[str, str, Optional[str], Optional[int], Optional[int]]:
    """
    Saves file with UUID filename into storage_backend under media/{sub_folder}/.
    Generates thumbnail if image and NOT encrypted.
    Returns (stored_filename, storage_path, thumbnail_path, width, height).
    """
    ensure_media_dirs()

    unique_id = uuid.uuid4().hex
    stored_filename = f"{unique_id}{ext}"
    sub_folder = "images" if media_type == "image" else ("videos" if media_type == "video" else "files")
    object_key = f"media/{sub_folder}/{stored_filename}"

    file.file.seek(0)
    file_bytes = file.file.read()
    file.file.seek(0)

    # Store file in storage backend
    storage_backend.put(object_key, file_bytes, content_type=file.content_type)
    storage_path = f"uploads/{object_key}"

    thumbnail_path = None
    width = None
    height = None

    # Zero-knowledge: If payload is encrypted ciphertext, NEVER attempt server-side thumbnailing!
    if media_type == "image" and not is_encrypted:
        try:
            from PIL import Image  # type: ignore
            with Image.open(io.BytesIO(file_bytes)) as img:
                width, height = img.size
                img.thumbnail((300, 300))
                if img.mode in ("RGBA", "P"):
                    img = img.convert("RGB")
                thumb_buffer = io.BytesIO()
                img.save(thumb_buffer, "JPEG", quality=80)
                thumb_buffer.seek(0)
                thumb_key = f"media/thumbnails/thumb_{stored_filename}"
                storage_backend.put(thumb_key, thumb_buffer.getvalue(), content_type="image/jpeg")
                thumbnail_path = f"uploads/{thumb_key}"
        except Exception:
            thumbnail_path = None

    return stored_filename, storage_path, thumbnail_path, width, height


def delete_physical_file(storage_path: Optional[str], thumbnail_path: Optional[str] = None):
    """
    Safely removes storage object and optional thumbnail from storage backend.
    """
    if storage_path:
        storage_backend.delete(storage_path)

    if thumbnail_path:
        storage_backend.delete(thumbnail_path)
