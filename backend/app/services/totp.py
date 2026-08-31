import base64
import hashlib
import hmac
import struct
import time
import secrets
from typing import List, Tuple


def generate_totp_secret() -> str:
    """Generate a high-entropy 20-byte base32 secret (32 chars) for TOTP."""
    raw = secrets.token_bytes(20)
    return base64.b32encode(raw).decode("utf-8").replace("=", "")


def get_totp_uri(secret: str, email: str, issuer: str = "TwoOfUs") -> str:
    """Generate standard otpauth URI compatible with Google/Microsoft Authenticator."""
    clean_secret = secret.strip().replace(" ", "").upper()
    return f"otpauth://totp/{issuer}:{email}?secret={clean_secret}&issuer={issuer}&algorithm=SHA1&digits=6&period=30"


def generate_totp_code(secret: str, time_step: int = 30, digits: int = 6, for_time: float | None = None) -> str:
    """Generate standard RFC 6238 6-digit TOTP code for a given timestamp."""
    if for_time is None:
        for_time = time.time()
    secret_clean = secret.strip().replace(" ", "").upper()
    padding = "=" * ((8 - len(secret_clean) % 8) % 8)
    key = base64.b32decode(secret_clean + padding)
    intervals = int(for_time // time_step)
    msg = struct.pack(">Q", intervals)
    h = hmac.new(key, msg, hashlib.sha1).digest()
    offset = h[-1] & 0x0F
    code = (struct.unpack(">I", h[offset:offset + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(code).zfill(digits)


def verify_totp_code(secret: str, code: str, window: int = 1) -> bool:
    """Validate 6-digit code with time drift window (prevents clock skew issues)."""
    code_str = str(code).strip()
    if len(code_str) != 6 or not code_str.isdigit():
        return False
    now = time.time()
    for offset in range(-window, window + 1):
        expected = generate_totp_code(secret, for_time=now + (offset * 30))
        if hmac.compare_digest(expected, code_str):
            return True
    return False


def generate_backup_codes(count: int = 8) -> Tuple[List[str], List[str]]:
    """Generate human-readable backup recovery codes (e.g. ABCD-1234) and their SHA-256 hashes."""
    plain_codes = []
    hashed_codes = []
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for _ in range(count):
        part1 = "".join(secrets.choice(chars) for _ in range(4))
        part2 = "".join(secrets.choice(chars) for _ in range(4))
        code = f"{part1}-{part2}"
        plain_codes.append(code)
        hashed_codes.append(hash_backup_code(code))
    return plain_codes, hashed_codes


def hash_backup_code(code: str) -> str:
    """Normalize and hash backup recovery code."""
    normalized = code.strip().replace("-", "").replace(" ", "").upper()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def verify_and_consume_backup_code(code: str, hashed_codes: List[str]) -> Tuple[bool, List[str]]:
    """Verify if a backup code exists in the list; if so, remove it (single-use) and return updated list."""
    target_hash = hash_backup_code(code)
    for i, h in enumerate(hashed_codes):
        if hmac.compare_digest(h, target_hash):
            updated = list(hashed_codes)
            updated.pop(i)
            return True, updated
    return False, hashed_codes
