import os
import sys
import io
import unittest

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
from backend.app.models import User, Pair, DiaryMemory

# Use an isolated test database
SQLALCHEMY_DATABASE_URL = "sqlite:///./test_diary_memories.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


class DiaryMemoriesUnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        db = TestingSessionLocal()
        cls.user_a = User(
            email="alice_diary@twoofus.app",
            username="alice_diary",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_alice"
        )
        cls.user_b = User(
            email="bob_diary@twoofus.app",
            username="bob_diary",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_bob"
        )
        cls.user_c = User(
            email="charlie_unpaired@twoofus.app",
            username="charlie_unpaired",
            password_hash=hash_password("Pass123!"),
            public_key="pubkey_charlie"
        )
        db.add_all([cls.user_a, cls.user_b, cls.user_c])
        db.commit()
        db.refresh(cls.user_a)
        db.refresh(cls.user_b)
        db.refresh(cls.user_c)

        pair = Pair(user1_id=cls.user_a.id, user2_id=cls.user_b.id, connection_pin="999999")
        db.add(pair)
        db.commit()

        cls.token_a = create_access_token({"sub": str(cls.user_a.id), "email": cls.user_a.email})
        cls.token_b = create_access_token({"sub": str(cls.user_b.id), "email": cls.user_b.email})
        cls.token_c = create_access_token({"sub": str(cls.user_c.id), "email": cls.user_c.email})
        db.close()

    def setUp(self):
        app.dependency_overrides[get_db] = override_get_db

    @classmethod
    def tearDownClass(cls):
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("./test_diary_memories.db"):
            try:
                os.remove("./test_diary_memories.db")
            except Exception:
                pass

    def test_01_create_text_diary_entry(self):
        # Alice posts a diary entry on 2026-08-20
        res = client.post(
            "/memories/create",
            headers={"Authorization": f"Bearer {self.token_a}"},
            data={
                "partner_id": str(self.user_b.id),
                "entry_date": "2026-08-20",
                "content": "Sunset at the beach with you ❤️",
                "mood_emoji": "❤️"
            }
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["entry_date"], "2026-08-20")
        self.assertEqual(data["content"], "Sunset at the beach with you ❤️")
        self.assertEqual(data["mood_emoji"], "❤️")
        self.assertEqual(data["sender_id"], self.user_a.id)
        self.assertEqual(data["receiver_id"], self.user_b.id)

    def test_02_create_photo_memory(self):
        # Bob attaches a photo memory for 2026-08-14
        dummy_image = io.BytesIO(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xff\xdb\x00C\x00")
        res = client.post(
            "/memories/create",
            headers={"Authorization": f"Bearer {self.token_b}"},
            data={
                "partner_id": str(self.user_a.id),
                "entry_date": "2026-08-14",
                "content": "Anniversary dinner celebration! 🥂",
                "mood_emoji": "🥂"
            },
            files={"photo": ("anniversary.jpg", dummy_image, "image/jpeg")}
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIsNotNone(data["image_url"])
        self.assertTrue(data["image_url"].startswith("uploads/memories/"))
        self.assertEqual(data["entry_date"], "2026-08-14")

    def test_03_partner_fetches_all_shared_memories(self):
        # Alice fetches memories shared with Bob
        res = client.get(
            f"/memories/pair/{self.user_b.id}",
            headers={"Authorization": f"Bearer {self.token_a}"}
        )
        self.assertEqual(res.status_code, 200)
        entries = res.json()
        self.assertEqual(len(entries), 2)
        # Verify both text and photo entries are present
        self.assertTrue(any(e["content"] == "Sunset at the beach with you ❤️" for e in entries))
        self.assertTrue(any(e["mood_emoji"] == "🥂" and e["image_url"] is not None for e in entries))

    def test_04_unpaired_user_access_blocked(self):
        # Charlie (unpaired) tries to view Alice's memories
        res = client.get(
            f"/memories/pair/{self.user_a.id}",
            headers={"Authorization": f"Bearer {self.token_c}"}
        )
        self.assertEqual(res.status_code, 403)

    def test_05_delete_memory_entry(self):
        # Create a temp entry
        res = client.post(
            "/memories/create",
            headers={"Authorization": f"Bearer {self.token_a}"},
            data={
                "partner_id": str(self.user_b.id),
                "entry_date": "2026-08-01",
                "content": "A note to be removed",
            }
        )
        self.assertEqual(res.status_code, 200)
        mem_id = res.json()["id"]

        # Delete it
        del_res = client.delete(
            f"/memories/{mem_id}",
            headers={"Authorization": f"Bearer {self.token_a}"}
        )
        self.assertEqual(del_res.status_code, 200)

        # Confirm deleted
        fetch_res = client.get(
            f"/memories/pair/{self.user_b.id}",
            headers={"Authorization": f"Bearer {self.token_a}"}
        )
        self.assertTrue(all(e["id"] != mem_id for e in fetch_res.json()))


if __name__ == "__main__":
    unittest.main()
