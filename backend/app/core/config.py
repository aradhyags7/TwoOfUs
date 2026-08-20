from dotenv import load_dotenv
import os

# Load variables from .env
load_dotenv()


class Settings:
    SECRET_KEY = os.getenv(
        "SECRET_KEY",
        "twoofus_super_secret_key_2026"
    )

    ALGORITHM = os.getenv(
        "ALGORITHM",
        "HS256"
    )

    ACCESS_TOKEN_EXPIRE_MINUTES = int(
        os.getenv(
            "ACCESS_TOKEN_EXPIRE_MINUTES",
            525600  # 1 year validity for couple sessions
        )
    )

    MEDIA_DIR = os.getenv("MEDIA_DIR", "media")
    MAX_IMAGE_SIZE_BYTES = 25 * 1024 * 1024  # 25 MB
    MAX_VIDEO_SIZE_BYTES = 100 * 1024 * 1024 # 100 MB
    MAX_FILE_SIZE_BYTES = 50 * 1024 * 1024   # 50 MB


settings = Settings()