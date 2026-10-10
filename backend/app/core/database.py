import os
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL")

# Enforce PostgreSQL in production
if not DATABASE_URL:
    if os.getenv("RENDER") or os.getenv("ENV") == "production":
        raise RuntimeError("DATABASE_URL environment variable is required in production (PostgreSQL required, SQLite prohibited).")
    DATABASE_URL = "sqlite:///./twoofus.db"
elif (os.getenv("RENDER") or os.getenv("ENV") == "production") and DATABASE_URL.startswith("sqlite"):
    raise RuntimeError("PostgreSQL DATABASE_URL is required in production. SQLite is not permitted on ephemeral cloud instances.")

# Render / Heroku compatibility: convert postgres:// to postgresql://
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

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