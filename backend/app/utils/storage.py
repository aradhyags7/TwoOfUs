import os
import uuid
import shutil
from typing import Tuple, Optional
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


def ensure_media_dirs():
    base = settings.MEDIA_DIR
    dirs = [
        os.path.join(base, "images"),
        os.path.join(base, "videos"),
        os.path.join(base, "files"),
        os.path.join(base, "thumbnails"),
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
    ext: str
) -> Tuple[str, str, Optional[str], Optional[int], Optional[int]]:
    """
    Saves file with UUID filename into settings.MEDIA_DIR/{type}/.
    Generates thumbnail if image.
    Returns (stored_filename, storage_path, thumbnail_path, width, height).
    """
    ensure_media_dirs()

    unique_id = uuid.uuid4().hex
    stored_filename = f"{unique_id}{ext}"
    sub_folder = "images" if media_type == "image" else ("videos" if media_type == "video" else "files")
    storage_path = os.path.join(settings.MEDIA_DIR, sub_folder, stored_filename)

    with open(storage_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    thumbnail_path = None
    width = None
    height = None

    # Generate image thumbnail and dimensions using Pillow if available
    if media_type == "image":
        try:
            from PIL import Image  # type: ignore
            with Image.open(storage_path) as img:
                width, height = img.size
                img.thumbnail((300, 300))
                thumb_name = f"thumb_{stored_filename}"
                thumbnail_path = os.path.join(settings.MEDIA_DIR, "thumbnails", thumb_name)
                # Convert RGBA to RGB for JPEG compatibility if needed
                if img.mode in ("RGBA", "P"):
                    img = img.convert("RGB")
                img.save(thumbnail_path, "JPEG", quality=80)
        except Exception:
            thumbnail_path = None

    return stored_filename, storage_path, thumbnail_path, width, height


def delete_physical_file(storage_path: Optional[str], thumbnail_path: Optional[str] = None):
    """
    Safely removes storage file and optional thumbnail from disk.
    """
    if storage_path and os.path.exists(storage_path):
        try:
            os.remove(storage_path)
        except Exception as e:
            print(f"Error removing file {storage_path}: {e}")

    if thumbnail_path and os.path.exists(thumbnail_path):
        try:
            os.remove(thumbnail_path)
        except Exception as e:
            print(f"Error removing thumbnail {thumbnail_path}: {e}")
