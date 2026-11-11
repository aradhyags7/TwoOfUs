import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from backend.app.main import app, get_db
from backend.app.core.database import Base
from backend.app.core.security import hash_password, create_access_token
from backend.app.core.rate_limiter import rate_limit_login, rate_limit_otp, rate_limit_pin
from backend.app.models import User, Pair
from backend.app.services.totp import generate_totp_secret, generate_totp_code

SQLALCHEMY_DATABASE_URL = "sqlite:///./test_tier1_security.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


client = TestClient(app)


class Tier1SecurityUnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        db = TestingSessionLocal()
        cls.user = User(
            email="tier1_user@twoofus.app",
            username="tier1_user",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_tier1"
        )
        db.add(cls.user)
        db.commit()
        db.refresh(cls.user)

        cls.token = create_access_token({"sub": str(cls.user.id), "email": cls.user.email})
        db.close()

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db
        # Reset rate limiters before each test to ensure test isolation
        rate_limit_login.limiter.reset()
        rate_limit_otp.limiter.reset()
        rate_limit_pin.limiter.reset()

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("./test_tier1_security.db"):
            try:
                os.remove("./test_tier1_security.db")
            except Exception:
                pass

    def test_01_security_headers_present(self):
        """Verify standard defensive HTTP security headers are injected on API responses."""
        res = client.get("/health")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.headers.get("X-Content-Type-Options"), "nosniff")
        self.assertEqual(res.headers.get("X-Frame-Options"), "DENY")
        self.assertIn("max-age=31536000", res.headers.get("Strict-Transport-Security", ""))
        self.assertEqual(res.headers.get("Referrer-Policy"), "strict-origin-when-cross-origin")

    def test_02_2fa_disable_rejects_expired_email_otp(self):
        """Verify that an expired email OTP cannot be used to disable 2FA."""
        db = TestingSessionLocal()
        user = db.query(User).filter(User.id == self.user.id).first()
        user.is_2fa_enabled = True
        user.two_factor_method = "email"
        user.email_2fa_otp = "123456"
        # Backdate expiration by 5 minutes
        user.email_2fa_expires_at = datetime.now(timezone.utc) - timedelta(minutes=5)
        db.commit()
        db.close()

        # Attempt to disable 2FA using the expired OTP
        res = client.post(
            "/2fa/disable",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"code": "123456"}
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid password or verification code", res.json()["detail"])

        # Confirm 2FA is still enabled
        db = TestingSessionLocal()
        user = db.query(User).filter(User.id == self.user.id).first()
        self.assertTrue(user.is_2fa_enabled)
        db.close()

    def test_03_2fa_disable_succeeds_with_valid_email_otp(self):
        """Verify that a valid, unexpired email OTP disables 2FA and purges secrets."""
        db = TestingSessionLocal()
        user = db.query(User).filter(User.id == self.user.id).first()
        user.is_2fa_enabled = True
        user.two_factor_method = "email"
        user.email_2fa_otp = "654321"
        user.email_2fa_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
        db.commit()
        db.close()

        res = client.post(
            "/2fa/disable",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"code": "654321"}
        )
        self.assertEqual(res.status_code, 200)

        # Confirm 2FA is disabled and secrets cleared
        db = TestingSessionLocal()
        user = db.query(User).filter(User.id == self.user.id).first()
        self.assertFalse(user.is_2fa_enabled)
        self.assertIsNone(user.email_2fa_otp)
        self.assertIsNone(user.email_2fa_expires_at)
        db.close()

    def test_04_totp_replay_prevention(self):
        """Verify RFC 6238 replay protection: the same TOTP code cannot authenticate two sessions."""
        secret = generate_totp_secret()
        db = TestingSessionLocal()
        user = db.query(User).filter(User.id == self.user.id).first()
        user.is_2fa_enabled = True
        user.two_factor_method = "totp"
        user.totp_secret = secret
        user.last_totp_time_step = None
        db.commit()
        db.close()

        totp_code = generate_totp_code(secret)

        # Session 1 login produces temp token
        temp_token_1 = create_access_token({"sub": str(self.user.id), "type": "2fa_pending"})
        res_v1 = client.post("/2fa/verify-login", json={"temp_token": temp_token_1, "code": totp_code})
        self.assertEqual(res_v1.status_code, 200)
        self.assertIn("access_token", res_v1.json())

        # Session 2 attempts immediate replay with the same TOTP code in the same 30s window
        temp_token_2 = create_access_token({"sub": str(self.user.id), "type": "2fa_pending"})
        res_v2 = client.post("/2fa/verify-login", json={"temp_token": temp_token_2, "code": totp_code})
        self.assertEqual(res_v2.status_code, 401)
        self.assertIn("Invalid", res_v2.json()["detail"])

    def test_05_rate_limiter_enforcement(self):
        """Verify that sending requests beyond the configured limit triggers HTTP 429."""
        from backend.app.core.rate_limiter import create_rate_limiter
        strict_limiter = create_rate_limiter(max_requests=3, window_seconds=60, prefix="test_strict")
        app.dependency_overrides[rate_limit_otp] = strict_limiter

        temp_token = create_access_token({"sub": str(self.user.id), "type": "2fa_pending"})

        # Send 3 requests (within threshold)
        for _ in range(3):
            res = client.post("/2fa/verify-login", json={"temp_token": temp_token, "code": "000000"})
            self.assertIn(res.status_code, [400, 401])

        # 4th request must trigger HTTP 429 Too Many Requests
        res_blocked = client.post("/2fa/verify-login", json={"temp_token": temp_token, "code": "000000"})
        self.assertEqual(res_blocked.status_code, 429)
        self.assertIn("Too many requests", res_blocked.json()["detail"])
        self.assertIn("Retry-After", res_blocked.headers)

        app.dependency_overrides.pop(rate_limit_otp, None)

    def test_06_call_signaling_bearer_authorization(self):
        """Verify call signaling endpoints accept Authorization: Bearer <token> without query parameters."""
        # 1. /call/turn-credentials with Bearer header
        res_turn = client.get(
            "/call/turn-credentials",
            headers={"Authorization": f"Bearer {self.token}"}
        )
        self.assertEqual(res_turn.status_code, 200)
        self.assertIn("uris", res_turn.json())

        # 2. /call/ticket with Bearer header
        res_ticket = client.post(
            "/call/ticket",
            headers={"Authorization": f"Bearer {self.token}"}
        )
        self.assertEqual(res_ticket.status_code, 200)
        self.assertIn("ticket", res_ticket.json())

        # 3. /call/device-token with Bearer header
        res_dev = client.post(
            "/call/device-token",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"token": "sample_fcm_token_123", "platform": "android"}
        )
        self.assertEqual(res_dev.status_code, 200)
        self.assertEqual(res_dev.json()["status"], "registered")


if __name__ == "__main__":
    unittest.main()
