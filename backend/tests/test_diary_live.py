import os
import json
import uuid
import urllib.request
import urllib.error
import unittest
from typing import Optional, Dict, Any

BASE_URL = "http://127.0.0.1:8000"


def make_request(
    method: str,
    path: str,
    data: Optional[Dict[str, Any]] = None,
    token: Optional[str] = None,
    raw_body: Optional[bytes] = None,
    headers: Optional[Dict[str, str]] = None
):
    url = f"{BASE_URL}{path}"
    req_headers = headers or {}
    if token:
        req_headers["Authorization"] = f"Bearer {token}"

    body_bytes = raw_body
    if data is not None and "Content-Type" not in req_headers:
        req_headers["Content-Type"] = "application/json"
        body_bytes = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=body_bytes, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


class LiveDiaryMemoriesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        suffix = uuid.uuid4().hex[:6]
        cls.u1_email = f"duser1_{suffix}@test.com"
        cls.u2_email = f"duser2_{suffix}@test.com"
        cls.u3_email = f"duser3_{suffix}@test.com"

        # Register users
        for email, uname in [(cls.u1_email, "du1"), (cls.u2_email, "du2"), (cls.u3_email, "du3")]:
            status, body, _ = make_request("POST", "/register", {"email": email, "username": uname + suffix, "password": "Password123!"})
            assert status == 200, f"Failed register: {body}"

        # Login users
        _, b1, _ = make_request("POST", "/login", {"email": cls.u1_email, "password": "Password123!"})
        d1 = json.loads(b1)
        cls.u1_id = d1["user_id"]
        cls.token1 = d1["access_token"]

        _, b2, _ = make_request("POST", "/login", {"email": cls.u2_email, "password": "Password123!"})
        d2 = json.loads(b2)
        cls.u2_id = d2["user_id"]
        cls.token2 = d2["access_token"]

        _, b3, _ = make_request("POST", "/login", {"email": cls.u3_email, "password": "Password123!"})
        d3 = json.loads(b3)
        cls.u3_id = d3["user_id"]
        cls.token3 = d3["access_token"]

        # Pair User 1 and User 2 via PIN
        _, pin_body, _ = make_request("GET", f"/generate-pin/{cls.u1_id}", token=cls.token1)
        pin_code = json.loads(pin_body)["pin"]
        status, _, _ = make_request("POST", "/connect-by-pin", {"user_id": cls.u2_id, "pin_code": pin_code}, token=cls.token2)
        assert status == 200

    def test_01_create_and_fetch_diary_entry(self):
        boundary = "----WebKitFormBoundary" + uuid.uuid4().hex
        body_parts = [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"partner_id\"\r\n\r\n{self.u2_id}\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"entry_date\"\r\n\r\n2026-08-20\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nFirst sunset date together ❤️\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"mood_emoji\"\r\n\r\n❤️\r\n".encode(),
            f"--{boundary}--\r\n".encode(),
        ]
        payload = b"".join(body_parts)

        status, resp, _ = make_request(
            "POST",
            "/memories/create",
            token=self.token1,
            raw_body=payload,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
        )
        self.assertEqual(status, 200)
        data = json.loads(resp)
        self.assertEqual(data["entry_date"], "2026-08-20")
        self.assertEqual(data["mood_emoji"], "❤️")
        self.assertEqual(data["content"], "First sunset date together ❤️")

        # Partner queries memories
        status, resp, _ = make_request("GET", f"/memories/pair/{self.u1_id}", token=self.token2)
        self.assertEqual(status, 200)
        memories = json.loads(resp)
        self.assertTrue(len(memories) >= 1)
        self.assertTrue(any(m["id"] == data["id"] for m in memories))

    def test_02_unpaired_access_blocked(self):
        # User 3 attempts to view memories of User 1
        status, _, _ = make_request("GET", f"/memories/pair/{self.u1_id}", token=self.token3)
        self.assertEqual(status, 403)

    def test_03_delete_memory(self):
        boundary = "----WebKitFormBoundary" + uuid.uuid4().hex
        body_parts = [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"partner_id\"\r\n\r\n{self.u2_id}\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"entry_date\"\r\n\r\n2026-08-01\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nTemp Note\r\n".encode(),
            f"--{boundary}--\r\n".encode()
        ]
        status, resp, _ = make_request(
            "POST",
            "/memories/create",
            token=self.token1,
            raw_body=b"".join(body_parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
        )
        mem_id = json.loads(resp)["id"]

        status, _, _ = make_request("DELETE", f"/memories/{mem_id}", token=self.token1)
        self.assertEqual(status, 200)

        _, resp, _ = make_request("GET", f"/memories/pair/{self.u2_id}", token=self.token1)
        mems = json.loads(resp)
        self.assertTrue(all(m["id"] != mem_id for m in mems))


if __name__ == "__main__":
    unittest.main()
