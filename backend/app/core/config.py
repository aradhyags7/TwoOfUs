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

    # SMTP Email Configuration
    SMTP_HOST = os.getenv("SMTP_HOST", "")
    SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER = os.getenv("SMTP_USER", "")
    SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
    SMTP_FROM_EMAIL = os.getenv("SMTP_FROM_EMAIL", "")
    SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "true").lower() in ("true", "1", "yes")
    SMTP_USE_SSL = os.getenv("SMTP_USE_SSL", "false").lower() in ("true", "1", "yes")

    # Cloud HTTP Email APIs (Works on Render, Heroku, AWS where outbound SMTP ports 25/465/587 are blocked)
    RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
    BREVO_API_KEY = os.getenv("BREVO_API_KEY", "")
    SENDGRID_API_KEY = os.getenv("SENDGRID_API_KEY", "")


settings = Settings()