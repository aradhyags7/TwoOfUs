import os
from sqlalchemy.orm import Session
from ..core.config import settings
from ..models.media import Media

def cleanup_orphaned_media_files(db: Session) -> dict:
    """
    Scans media storage directories and removes physical files on disk
    that no longer have a corresponding entry in the Media database table.
    """
    media_records = db.query(Media).all()
    valid_paths = set()

    for item in media_records:
        if item.storage_path:
            valid_paths.add(os.path.abspath(str(item.storage_path)))
        if item.thumbnail_path:
            valid_paths.add(os.path.abspath(str(item.thumbnail_path)))

    subfolders = ["images", "videos", "files", "thumbnails"]
    deleted_files = []
    freed_bytes = 0

    for sub in subfolders:
        folder_path = os.path.join(settings.MEDIA_DIR, sub)
        if not os.path.exists(folder_path):
            continue

        for filename in os.listdir(folder_path):
            file_abs_path = os.path.abspath(os.path.join(folder_path, filename))
            if os.path.isfile(file_abs_path) and file_abs_path not in valid_paths:
                try:
                    size = os.path.getsize(file_abs_path)
                    os.remove(file_abs_path)
                    deleted_files.append(file_abs_path)
                    freed_bytes += size
                except Exception as e:
                    print(f"Error removing orphan file {file_abs_path}: {e}")

    return {
        "deleted_count": len(deleted_files),
        "freed_bytes": freed_bytes,
        "deleted_files": deleted_files,
    }
