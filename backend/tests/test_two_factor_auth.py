import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.services.totp import generate_totp_code

client = TestClient(app)


class TestTwoFactorAuth:
    test_user = {
        "email": "twofactor_user@test.com",
        "username": "twofactor_user",
        "password": "Password123!"
    }
    user_token = None
    setup_secret = None
    backup_codes = None

    def test_01_register_and_login_without_2fa(self):
        # Register
        reg_res = client.post("/register", json=self.test_user)
        assert reg_res.status_code in [200, 400]

        # Login without 2FA
        login_res = client.post("/login", json={
            "email": self.test_user["email"],
            "password": self.test_user["password"]
        })
        assert login_res.status_code == 200
        data = login_res.json()
        assert "access_token" in data
        assert data.get("requires_2fa") is None
        TestTwoFactorAuth.user_token = data["access_token"]

    def test_02_get_initial_2fa_status(self):
        res = client.get(
            "/2fa/status",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"}
        )
        assert res.status_code == 200
        data = res.json()
        assert data["is_2fa_enabled"] is False

    def test_03_setup_2fa_generates_secret_and_codes(self):
        res = client.post(
            "/2fa/setup",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"}
        )
        assert res.status_code == 200
        data = res.json()
        assert "secret" in data
        assert "otpauth_url" in data
        assert "backup_codes" in data
        assert len(data["backup_codes"]) == 8
        TestTwoFactorAuth.setup_secret = data["secret"]
        TestTwoFactorAuth.backup_codes = data["backup_codes"]

    def test_04_enable_2fa_invalid_code_rejected(self):
        res = client.post(
            "/2fa/enable",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"},
            json={
                "code": "000000",
                "secret": TestTwoFactorAuth.setup_secret,
                "backup_codes": TestTwoFactorAuth.backup_codes
            }
        )
        assert res.status_code == 400

    def test_05_enable_2fa_valid_code_succeeds(self):
        valid_code = generate_totp_code(TestTwoFactorAuth.setup_secret)
        res = client.post(
            "/2fa/enable",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"},
            json={
                "code": valid_code,
                "secret": TestTwoFactorAuth.setup_secret,
                "backup_codes": TestTwoFactorAuth.backup_codes
            }
        )
        assert res.status_code == 200

        # Check status is now enabled
        status_res = client.get(
            "/2fa/status",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"}
        )
        assert status_res.status_code == 200
        assert status_res.json()["is_2fa_enabled"] is True
        assert status_res.json()["remaining_backup_codes"] == 8

    def test_06_login_intercepted_by_2fa(self):
        login_res = client.post("/login", json={
            "email": self.test_user["email"],
            "password": self.test_user["password"]
        })
        assert login_res.status_code == 200
        data = login_res.json()
        assert data.get("requires_2fa") is True
        assert "temp_token" in data

        # Verify login with valid TOTP code
        temp_token = data["temp_token"]
        valid_code = generate_totp_code(TestTwoFactorAuth.setup_secret)

        verify_res = client.post("/2fa/verify-login", json={
            "temp_token": temp_token,
            "code": valid_code
        })
        assert verify_res.status_code == 200
        verify_data = verify_res.json()
        assert "access_token" in verify_data
        assert verify_data["email"] == self.test_user["email"]

    def test_07_login_with_backup_recovery_code(self):
        login_res = client.post("/login", json={
            "email": self.test_user["email"],
            "password": self.test_user["password"]
        })
        assert login_res.status_code == 200
        data = login_res.json()
        assert data.get("requires_2fa") is True
        temp_token = data["temp_token"]

        # Use the first backup code
        used_code = TestTwoFactorAuth.backup_codes[0]
        verify_res = client.post("/2fa/verify-login", json={
            "temp_token": temp_token,
            "code": used_code
        })
        assert verify_res.status_code == 200
        new_token = verify_res.json()["access_token"]

        # Verify that remaining backup codes count decreased from 8 to 7
        status_res = client.get(
            "/2fa/status",
            headers={"Authorization": f"Bearer {new_token}"}
        )
        assert status_res.status_code == 200
        assert status_res.json()["remaining_backup_codes"] == 7

        # Re-using the same backup code MUST be rejected
        login_res2 = client.post("/login", json={
            "email": self.test_user["email"],
            "password": self.test_user["password"]
        })
        temp_token2 = login_res2.json()["temp_token"]
        verify_res2 = client.post("/2fa/verify-login", json={
            "temp_token": temp_token2,
            "code": used_code
        })
        assert verify_res2.status_code == 401

    def test_08_disable_2fa_with_password(self):
        res = client.post(
            "/2fa/disable",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"},
            json={"password": self.test_user["password"]}
        )
        assert res.status_code == 200

        # Verify status is disabled
        status_res = client.get(
            "/2fa/status",
            headers={"Authorization": f"Bearer {TestTwoFactorAuth.user_token}"}
        )
        assert status_res.status_code == 200
        assert status_res.json()["is_2fa_enabled"] is False

        # Login directly without 2FA
        login_res = client.post("/login", json={
            "email": self.test_user["email"],
            "password": self.test_user["password"]
        })
        assert login_res.status_code == 200
        assert login_res.json().get("requires_2fa") is None
        assert "access_token" in login_res.json()
