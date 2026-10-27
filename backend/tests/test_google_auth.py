import os
import sys
import uuid
import pytest
from unittest.mock import patch, MagicMock

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root_dir = os.path.dirname(backend_dir)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
if root_dir not in sys.path:
    sys.path.insert(0, root_dir)

from fastapi.testclient import TestClient
from backend.app.main import app, run_auto_migrations
from backend.app.core.database import SessionLocal
from backend.app.models.user import User

run_auto_migrations()
client = TestClient(app)
_test_suffix = uuid.uuid4().hex[:6]



class TestGoogleAuth:
    def test_01_google_auth_missing_token(self):
        res = client.post("/auth/google", json={"id_token": ""})
        assert res.status_code == 400
        assert "id_token is required" in res.json()["detail"]

    @patch("httpx.AsyncClient.get")
    def test_02_google_auth_invalid_token(self, mock_get):
        mock_resp = MagicMock()
        mock_resp.status_code = 401
        mock_resp.json.return_value = {"error_description": "Invalid Value"}
        mock_get.return_value = mock_resp

        res = client.post("/auth/google", json={"id_token": "invalid_fake_token"})
        assert res.status_code == 401
        assert "Invalid Google ID token" in res.json()["detail"]

    @patch("httpx.AsyncClient.get")
    def test_03_google_auth_unverified_email(self, mock_get):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "iss": "https://accounts.google.com",
            "sub": "google_sub_unverified",
            "email": f"unverified_{_test_suffix}@gmail.com",
            "email_verified": "false",
        }
        mock_get.return_value = mock_resp

        res = client.post("/auth/google", json={"id_token": "valid_structure_unverified"})
        assert res.status_code == 400
        assert "Google email is not verified" in res.json()["detail"]

    @patch("httpx.AsyncClient.get")
    def test_04_google_auth_new_user_success(self, mock_get):
        test_email = f"googlenew_{_test_suffix}@gmail.com"
        test_sub = f"sub_new_{_test_suffix}"
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "iss": "https://accounts.google.com",
            "sub": test_sub,
            "email": test_email,
            "email_verified": "true",
            "name": f"Google User {_test_suffix}",
            "picture": "https://lh3.googleusercontent.com/a/default-user=s96-c",
        }
        mock_get.return_value = mock_resp

        res = client.post("/auth/google", json={"id_token": "mocked_valid_token"})
        assert res.status_code == 200
        data = res.json()
        assert "access_token" in data
        assert data["email"] == test_email
        assert "user_id" in data
        assert "username" in data

        # Verify persisted in database
        db = SessionLocal()
        try:
            db_user = db.query(User).filter(User.email == test_email).first()
            assert db_user is not None
            assert db_user.google_id == test_sub
            assert db_user.avatar_url == "https://lh3.googleusercontent.com/a/default-user=s96-c"
        finally:
            db.close()

    @patch("httpx.AsyncClient.get")
    def test_05_google_auth_existing_user_login(self, mock_get):
        # First register normal user
        existing_email = f"existing_{_test_suffix}@gmail.com"
        reg_res = client.post("/register", json={
            "email": existing_email,
            "username": f"exist_{_test_suffix}",
            "password": "Password123!"
        })
        assert reg_res.status_code == 200

        # Now authenticate with Google using same email
        test_sub = f"sub_exist_{_test_suffix}"
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "iss": "https://accounts.google.com",
            "sub": test_sub,
            "email": existing_email,
            "email_verified": "true",
            "name": "Existing User",
        }
        mock_get.return_value = mock_resp

        res = client.post("/auth/google", json={"id_token": "mocked_valid_token"})
        assert res.status_code == 200
        data = res.json()
        assert "access_token" in data
        assert data["email"] == existing_email

        # Verify google_id was linked to existing user
        db = SessionLocal()
        try:
            db_user = db.query(User).filter(User.email == existing_email).first()
            assert db_user is not None
            assert db_user.google_id == test_sub
        finally:
            db.close()

    @patch("httpx.AsyncClient.get")
    def test_06_google_auth_with_2fa_enabled(self, mock_get):
        # Register user with 2FA
        twofa_email = f"twofa_google_{_test_suffix}@gmail.com"
        reg_res = client.post("/register", json={
            "email": twofa_email,
            "username": f"twofa_{_test_suffix}",
            "password": "Password123!"
        })
        assert reg_res.status_code == 200

        # Enable 2FA in DB
        db = SessionLocal()
        try:
            db_user = db.query(User).filter(User.email == twofa_email).first()
            db_user.is_2fa_enabled = True
            db_user.two_factor_method = "totp"
            db_user.totp_secret = "JBSWY3DPEHPK3PXP"
            db.commit()
        finally:
            db.close()

        # Google auth
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "iss": "https://accounts.google.com",
            "sub": f"sub_2fa_{_test_suffix}",
            "email": twofa_email,
            "email_verified": "true",
            "name": "2FA User",
        }
        mock_get.return_value = mock_resp

        res = client.post("/auth/google", json={"id_token": "mocked_valid_token"})
        assert res.status_code == 200
        data = res.json()
        assert data.get("requires_2fa") is True
        assert "temp_token" in data
        assert "user_id" in data

