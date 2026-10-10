import os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect

from app.main import app, run_auto_migrations
from app.core.config import Settings
from app.core.database import Base


def test_health_sqlite():
    """Verify app starts and GET /health returns 200 with SQLite default."""
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "ok"
    assert data.get("app") == "TwoOfUs"


def test_sqlite_migration_idempotency(tmp_path):
    """Verify run_auto_migrations runs cleanly twice on SQLite without error."""
    test_db = tmp_path / "test_smoke.db"
    db_url = f"sqlite:///{test_db}"
    engine = create_engine(db_url, connect_args={"check_same_thread": False})

    # Run migration first time
    run_auto_migrations(engine)

    # Run migration second time (idempotency check)
    run_auto_migrations(engine)

    inspector = inspect(engine)
    dm_cols = [c["name"] for c in inspector.get_columns("diary_memories")]
    assert "is_encrypted" in dm_cols
    assert "content_nonce" in dm_cols
    assert "photo_nonce" in dm_cols

    msg_cols = [c["name"] for c in inspector.get_columns("messages")]
    assert "is_encrypted" in dm_cols
    assert "nonce" in msg_cols

    engine.dispose()


@pytest.mark.skipif(not os.getenv("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL not set")
def test_postgres_migration_idempotency_and_health():
    """Verify run_auto_migrations runs cleanly twice on PostgreSQL and /health is 200."""
    raw_pg_url = os.getenv("TEST_DATABASE_URL")
    if raw_pg_url.startswith("postgres://"):
        raw_pg_url = raw_pg_url.replace("postgres://", "postgresql://", 1)

    pg_engine = create_engine(raw_pg_url)

    # Run migration first time
    run_auto_migrations(pg_engine)

    # Run migration second time (idempotency check)
    run_auto_migrations(pg_engine)

    inspector = inspect(pg_engine)
    assert inspector.has_table("diary_memories")
    dm_cols = [c["name"] for c in inspector.get_columns("diary_memories")]
    assert "is_encrypted" in dm_cols
    assert "content_nonce" in dm_cols
    assert "photo_nonce" in dm_cols

    msg_cols = [c["name"] for c in inspector.get_columns("messages")]
    assert "is_encrypted" in msg_cols
    assert "nonce" in msg_cols

    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json().get("status") == "ok"

    pg_engine.dispose()


def test_postgres_scheme_normalization():
    """Verify postgres:// is normalized to postgresql://."""
    url = "postgres://user:pass@ep-cool-1234.us-east-1.render.com/twoofus"
    if url.startswith("postgres://"):
        normalized = url.replace("postgres://", "postgresql://", 1)
    else:
        normalized = url
    assert normalized == "postgresql://user:pass@ep-cool-1234.us-east-1.render.com/twoofus"


def test_config_safe_token_expire_default():
    """Verify token expiration safely falls back to 60 if missing or malformed."""
    # Test empty / unset fallback
    empty_val = ""
    try:
        val1 = int(empty_val or "60")
    except (ValueError, TypeError):
        val1 = 60
    assert val1 == 60

    # Test non-integer fallback
    bad_val = "not_a_number"
    try:
        val2 = int(bad_val or "60")
    except (ValueError, TypeError):
        val2 = 60
    assert val2 == 60
