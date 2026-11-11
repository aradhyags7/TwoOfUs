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
from backend.app.models import User, Pair, ConnectionPin

SQLALCHEMY_DATABASE_URL = "sqlite:///./test_pairing_security.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


client = TestClient(app)


class PairingSecurityUnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        db = TestingSessionLocal()
        cls.user_a = User(
            email="pair_alice@twoofus.app",
            username="pair_alice",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_alice"
        )
        cls.user_b = User(
            email="pair_bob@twoofus.app",
            username="pair_bob",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_bob"
        )
        cls.user_c = User(
            email="pair_charlie@twoofus.app",
            username="pair_charlie",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_charlie"
        )
        cls.user_d = User(
            email="pair_diana@twoofus.app",
            username="pair_diana",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_diana"
        )
        db.add_all([cls.user_a, cls.user_b, cls.user_c, cls.user_d])
        db.commit()
        db.refresh(cls.user_a)
        db.refresh(cls.user_b)
        db.refresh(cls.user_c)
        db.refresh(cls.user_d)

        cls.token_a = create_access_token({"sub": str(cls.user_a.id), "email": cls.user_a.email})
        cls.token_b = create_access_token({"sub": str(cls.user_b.id), "email": cls.user_b.email})
        cls.token_c = create_access_token({"sub": str(cls.user_c.id), "email": cls.user_c.email})
        cls.token_d = create_access_token({"sub": str(cls.user_d.id), "email": cls.user_d.email})
        db.close()

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("./test_pairing_security.db"):
            try:
                os.remove("./test_pairing_security.db")
            except Exception:
                pass

    def test_01_pin_generation_and_replacement(self):
        # Alice generates a PIN
        res1 = client.get(f"/generate-pin/{self.user_a.id}", headers={"Authorization": f"Bearer {self.token_a}"})
        self.assertEqual(res1.status_code, 200)
        pin1 = res1.json()["pin"]
        self.assertEqual(len(pin1), 8)

        # Alice generates another PIN - the previous PIN should be invalidated
        res2 = client.get(f"/generate-pin/{self.user_a.id}", headers={"Authorization": f"Bearer {self.token_a}"})
        self.assertEqual(res2.status_code, 200)
        pin2 = res2.json()["pin"]
        self.assertEqual(len(pin2), 8)
        self.assertNotEqual(pin1, pin2)

        # Bob trying pin1 should fail (it was deleted / invalidated)
        res_old = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_b}"},
            json={"user_id": self.user_b.id, "pin_code": pin1}
        )
        self.assertEqual(res_old.status_code, 404)

    def test_02_self_pairing_rejected(self):
        # Alice generates a PIN and tries to connect to herself
        res_pin = client.get(f"/generate-pin/{self.user_a.id}", headers={"Authorization": f"Bearer {self.token_a}"})
        pin = res_pin.json()["pin"]

        res_self = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_a}"},
            json={"user_id": self.user_a.id, "pin_code": pin}
        )
        self.assertEqual(res_self.status_code, 400)
        self.assertIn("cannot connect to yourself", res_self.json()["detail"].lower())

    def test_03_expired_pin_rejected(self):
        # Charlie generates a PIN
        res_pin = client.get(f"/generate-pin/{self.user_c.id}", headers={"Authorization": f"Bearer {self.token_c}"})
        pin = res_pin.json()["pin"]

        # Backdate the expiration in the test DB
        db = TestingSessionLocal()
        pin_record = db.query(ConnectionPin).filter(ConnectionPin.pin_code == pin).first()
        self.assertIsNotNone(pin_record)
        pin_record.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        db.commit()
        db.close()

        # Diana tries to connect with the expired PIN
        res_expired = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_d}"},
            json={"user_id": self.user_d.id, "pin_code": pin}
        )
        self.assertEqual(res_expired.status_code, 400)
        self.assertIn("expired", res_expired.json()["detail"].lower())

    def test_04_successful_pair_and_pin_consumption(self):
        # Alice generates a valid PIN
        res_pin = client.get(f"/generate-pin/{self.user_a.id}", headers={"Authorization": f"Bearer {self.token_a}"})
        pin = res_pin.json()["pin"]

        # Bob connects using Alice's PIN
        res_connect = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_b}"},
            json={"user_id": self.user_b.id, "pin_code": pin}
        )
        self.assertEqual(res_connect.status_code, 200)
        body = res_connect.json()
        self.assertIn("pair_id", body)
        self.assertEqual(body["user1_id"], self.user_a.id)
        self.assertEqual(body["user2_id"], self.user_b.id)

        # Single-use check: Trying to reuse the same PIN must fail (already consumed / deleted)
        res_reuse = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_c}"},
            json={"user_id": self.user_c.id, "pin_code": pin}
        )
        self.assertEqual(res_reuse.status_code, 404)

    def test_05_paired_user_cannot_generate_pin(self):
        # Alice is now paired with Bob; she must not be able to generate a new PIN
        res = client.get(f"/generate-pin/{self.user_a.id}", headers={"Authorization": f"Bearer {self.token_a}"})
        self.assertEqual(res.status_code, 400)
        self.assertIn("already connected", res.json()["detail"].lower())

        # Bob also must not be able to generate a new PIN
        res_bob = client.get(f"/generate-pin/{self.user_b.id}", headers={"Authorization": f"Bearer {self.token_b}"})
        self.assertEqual(res_bob.status_code, 400)
        self.assertIn("already connected", res_bob.json()["detail"].lower())

    def test_06_paired_user_cannot_connect_to_another(self):
        # Charlie generates a valid PIN
        res_pin = client.get(f"/generate-pin/{self.user_c.id}", headers={"Authorization": f"Bearer {self.token_c}"})
        pin = res_pin.json()["pin"]

        # Bob (already paired with Alice) tries to connect with Charlie's PIN
        res = client.post(
            "/connect-by-pin",
            headers={"Authorization": f"Bearer {self.token_b}"},
            json={"user_id": self.user_b.id, "pin_code": pin}
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("already connected", res.json()["detail"].lower())


if __name__ == "__main__":
    unittest.main()
