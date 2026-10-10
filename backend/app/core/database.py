import os
import re
import time
from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker


def normalize_postgres_url(raw_url: str) -> str:
    """Normalizes Postgres URL for SQLAlchemy 2.x and preserves query params."""
    if not raw_url:
        return ""
    url = raw_url.strip()
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return url


def strip_channel_binding(url: str) -> str:
    """Removes channel_binding from URL query params if psycopg2 / pooler rejects it."""
    url = re.sub(r'([?&])channel_binding=[^&]*(&|$)', r'\1', url)
    return url.rstrip('?&')


DATABASE_URL = normalize_postgres_url(os.getenv("DATABASE_URL") or "")
DATABASE_URL_DIRECT = normalize_postgres_url(os.getenv("DATABASE_URL_DIRECT") or "")

# Fail soft if DATABASE_URL is unset, logging a loud warning instead of crashing
if not DATABASE_URL:
    if os.getenv("RENDER") or os.getenv("ENV") == "production":
        print("\n" + "!" * 70)
        print(" [DATABASE CONFIGURATION NOTICE] DATABASE_URL is not set!")
        print(" Falling back to local SQLite (sqlite:///./twoofus.db).")
        print(" WARNING: Local SQLite on Render ephemeral containers will not persist")
        print(" across redeploys. Link a managed PostgreSQL database via render.yaml")
        print(" or set DATABASE_URL in your Render dashboard environment variables.")
        print("!" * 70 + "\n")
    DATABASE_URL = "sqlite:///./twoofus.db"
elif (os.getenv("RENDER") or os.getenv("ENV") == "production") and DATABASE_URL.startswith("sqlite"):
    print("\n" + "!" * 70)
    print(" [DATABASE CONFIGURATION NOTICE] SQLite is active in production mode.")
    print(" Data stored locally in SQLite will be ephemeral across restarts.")
    print("!" * 70 + "\n")


def build_engine(url: str):
    """Builds a database engine with pooling tuned for serverless Postgres (Neon)."""
    if url.startswith("sqlite"):
        return create_engine(
            url,
            connect_args={"check_same_thread": False}
        )
    return create_engine(
        url,
        pool_pre_ping=True,
        pool_recycle=300,
        pool_size=5,
        max_overflow=5,
        connect_args={"connect_timeout": 10},
    )


# Configure main application engine
try:
    engine = build_engine(DATABASE_URL)
except Exception:
    if "channel_binding" in DATABASE_URL:
        DATABASE_URL = strip_channel_binding(DATABASE_URL)
        engine = build_engine(DATABASE_URL)
    else:
        raise

# Configure migration engine (uses direct URL if specified, else falls back to main engine)
if DATABASE_URL_DIRECT:
    migration_engine = build_engine(DATABASE_URL_DIRECT)
else:
    migration_engine = engine


def check_db_health() -> str:
    """Executes a cheap SELECT 1 query to report database health without crashing."""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return "ok"
    except Exception:
        return "error"


def attempt_cold_start_connection(target_engine, max_retries=1, delay=2.5):
    """Retries connection once to accommodate Neon scale-to-zero cold boot delays."""
    if target_engine.url.drivername.startswith("sqlite"):
        return
    for attempt in range(max_retries + 1):
        try:
            with target_engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            return
        except Exception as e:
            err_msg = str(e).lower()
            if "channel_binding" in err_msg:
                print("[DATABASE NOTICE] Channel binding rejected by pooler/libpq. Stripping channel_binding parameter.")
                global engine, DATABASE_URL
                DATABASE_URL = strip_channel_binding(DATABASE_URL)
                engine = build_engine(DATABASE_URL)
                target_engine = engine
            if attempt < max_retries:
                time.sleep(delay)
            else:
                print(f"[DATABASE NOTICE] Initial cold-start connection probe deferred: {e}")


# Cold start probe on module load
try:
    attempt_cold_start_connection(engine)
except Exception as e:
    print(f"[DATABASE NOTICE] Cold start probe exception ignored: {e}")

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

Base = declarative_base()


# Dependency for API routes
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()