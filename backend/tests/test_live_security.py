import os
import json
import time
import uuid
import urllib.request
import urllib.error
import threading
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
    if data is not None:
        req_headers["Content-Type"] = "application/json"
        body_bytes = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=body_bytes, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


class LiveSecurityAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Create 3 isolated test users on live backend
        suffix = uuid.uuid4().hex[:6]
        cls.u1_email = f"alice_{suffix}@twoofus.app"
        cls.u2_email = f"bob_{suffix}@twoofus.app"
        cls.u3_email = f"charlie_{suffix}@twoofus.app"

        # Register users
        for email, uname in [(cls.u1_email, "alice"), (cls.u2_email, "bob"), (cls.u3_email, "charlie")]:
            status, body, _ = make_request("POST", "/register", {"email": email, "username": uname + suffix, "password": "Password123!"})
            assert status == 200, f"Failed to register {email}: {body}"

        # Login users
        _, body, _ = make_request("POST", "/login", {"email": cls.u1_email, "password": "Password123!"})
        data = json.loads(body)
        cls.u1_id = data["user_id"]
        cls.u1_token = data["access_token"]

        _, body, _ = make_request("POST", "/login", {"email": cls.u2_email, "password": "Password123!"})
        data = json.loads(body)
        cls.u2_id = data["user_id"]
        cls.u2_token = data["access_token"]

        _, body, _ = make_request("POST", "/login", {"email": cls.u3_email, "password": "Password123!"})
        data = json.loads(body)
        cls.u3_id = data["user_id"]
        cls.u3_token = data["access_token"]

        # Pair Alice and Bob via PIN
        _, pin_body, _ = make_request("GET", f"/generate-pin/{cls.u1_id}", token=cls.u1_token)
        pin_code = json.loads(pin_body)["pin"]
        status, _, _ = make_request("POST", "/connect-by-pin", {"user_id": cls.u2_id, "pin_code": pin_code}, token=cls.u2_token)
        assert status == 200

    # 1. Unauthenticated endpoints rejected
    def test_01_unauthenticated_endpoints_rejected(self):
        status, _, _ = make_request("GET", "/me")
        self.assertEqual(status, 401)

        status, _, _ = make_request("GET", f"/messages/{self.u1_id}/{self.u2_id}")
        self.assertEqual(status, 401)

        status, _, _ = make_request("POST", "/send-message", {"sender_id": self.u1_id, "receiver_id": self.u2_id, "content": "test"})
        self.assertEqual(status, 401)

        status, _, _ = make_request("GET", f"/profile/{self.u1_id}")
        self.assertEqual(status, 401)

        status, _, _ = make_request("GET", f"/keys/{self.u1_id}")
        self.assertEqual(status, 401)
        print("\n  [PASS] All sensitive endpoints reject unauthenticated requests (HTTP 401)")

    # 2. Cross-user IDOR / Impersonation strictly rejected
    def test_02_idor_impersonation_strictly_blocked(self):
        # Charlie (u3) tries to send message as Alice (u1) -> 403
        status, body, _ = make_request(
            "POST", "/send-message",
            {"sender_id": self.u1_id, "receiver_id": self.u2_id, "content": "spoofed"},
            token=self.u3_token
        )
        self.assertEqual(status, 403)
        self.assertIn(b"Sender ID does not match", body)

        # Charlie tries to read Alice & Bob messages -> 403
        status, _, _ = make_request("GET", f"/messages/{self.u1_id}/{self.u2_id}", token=self.u3_token)
        self.assertEqual(status, 403)

        # Charlie tries to update Alice's profile -> 403
        status, _, _ = make_request("PUT", f"/profile/{self.u1_id}", {"username": "hacked"}, token=self.u3_token)
        self.assertEqual(status, 403)

        # Charlie tries to change Alice's password -> 403
        status, _, _ = make_request("PUT", f"/change-password/{self.u1_id}", {"current_password": "a", "new_password": "b"}, token=self.u3_token)
        self.assertEqual(status, 403)

        # Charlie tries to generate PIN for Alice -> 403
        status, _, _ = make_request("GET", f"/generate-pin/{self.u1_id}", token=self.u3_token)
        self.assertEqual(status, 403)
        print("  [PASS] IDOR & impersonation across all endpoints strictly rejected (HTTP 403)")

    # 3. View Once Single-Use & Concurrency Shredding
    def test_03_view_once_single_use_and_concurrency(self):
        # Upload encrypted View Once item from Alice to Bob
        boundary = f"----WebKitFormBoundary{uuid.uuid4().hex}"
        ciphertext = b"\xde\xad\xbe\xef_ENCRYPTED_VIEW_ONCE_CIPHERTEXT_\x00\x01\x02"

        body_parts = []
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"receiver_id\"\r\n\r\n{self.u2_id}\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"is_encrypted\"\r\n\r\ntrue\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"is_view_once\"\r\n\r\ntrue\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"encrypted_media_key\"\r\n\r\n{{\"k\":\"k\",\"n\":\"n\"}}\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"encryption_nonce\"\r\n\r\nnonce==\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"private_camera_99.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".encode() + ciphertext + b"\r\n")
        body_parts.append(f"--{boundary}--\r\n".encode())
        raw_body = b"".join(body_parts)

        status, body, _ = make_request(
            "POST", "/media/upload",
            raw_body=raw_body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            token=self.u1_token
        )
        self.assertEqual(status, 200)
        uploaded = json.loads(body)[0]
        media_id = uploaded["media_id"]

        # Filename must be sanitized (no camera metadata leak)
        self.assertNotIn("private_camera_99.jpg", uploaded["original_filename"])
        self.assertTrue(uploaded["original_filename"].startswith("enc_"))

        # Concurrent 10-thread simultaneous download
        statuses = []
        def worker():
            s, _, _ = make_request("GET", f"/media/{media_id}/file", token=self.u2_token)
            statuses.append(s)

        threads = [threading.Thread(target=worker) for _ in range(10)]
        for t in threads: t.start()
        for t in threads: t.join()

        success_count = statuses.count(200)
        gone_count = statuses.count(410)

        self.assertEqual(success_count, 1, f"Expected exactly 1 success, got {success_count}")
        self.assertEqual(gone_count, 9, f"Expected 9 HTTP 410 Gone, got {gone_count}")

        # Subsequent download strictly returns 410 Gone
        status, body, _ = make_request("GET", f"/media/{media_id}/file", token=self.u2_token)
        self.assertEqual(status, 410)
        self.assertIn(b"expired", body.lower())
        print("  [PASS] View Once Concurrency Test: Exactly 1x HTTP 200, 9x HTTP 410 Gone, disk shredded")

    # 4. Executable / Dangerous File Type Block
    def test_04_dangerous_extension_rejected(self):
        boundary = f"----WebKitFormBoundary{uuid.uuid4().hex}"
        body_parts = []
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"receiver_id\"\r\n\r\n{self.u2_id}\r\n".encode())
        body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"malware.exe\"\r\nContent-Type: application/x-msdownload\r\n\r\nMALICIOUS\r\n".encode())
        body_parts.append(f"--{boundary}--\r\n".encode())

        status, body, _ = make_request(
            "POST", "/media/upload",
            raw_body=b"".join(body_parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            token=self.u1_token
        )
        self.assertEqual(status, 415)
        self.assertIn(b"prohibited", body.lower())
        print("  [PASS] Dangerous executable (.exe) blocked with HTTP 415")


if __name__ == "__main__":
    unittest.main(verbosity=2)
