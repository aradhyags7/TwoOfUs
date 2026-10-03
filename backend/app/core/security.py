from typing import Any

from passlib.context import CryptContext
from jose import JWTError
from fastapi import HTTPException
from datetime import datetime, timedelta, timezone
from jose import jwt

from .config import settings


import bcrypt

def hash_password(password: str) -> str:
    pwd_bytes = password.encode('utf-8')[:72]
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(pwd_bytes, salt).decode('utf-8')


def verify_password(
    password: str,
    hashed_password: str | Any
) -> bool:
    pwd_bytes = password.encode('utf-8')[:72]
    try:
        return bcrypt.checkpw(pwd_bytes, str(hashed_password).encode('utf-8'))
    except Exception:
        return False


def decode_access_token(token: str):
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM]
        )
        return payload
    except JWTError as e:
        print(f"[JWT DECODE ERROR]: {e}")
        return None
    
    
def create_access_token(data: dict):

    to_encode = data.copy()

    expire = (
        datetime.now(timezone.utc)
        + timedelta(
            minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
        )
    )

    to_encode.update({
        "exp": expire
    })

    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )

    return encoded_jwt