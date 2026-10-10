import os
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = (os.getenv("DATABASE_URL") or "").strip()

# Normalize PostgreSQL URL scheme for SQLAlchemy 2.x
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

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

# Configure engine based on dialect (PostgreSQL vs SQLite)
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False}
    )
else:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_recycle=3600,
    )

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

Base = declarative_base()


# Dependency for future API routes
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()