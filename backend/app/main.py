from datetime import datetime, timezone, timedelta
import json
import os
import shutil
import string
from random import choices

from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from .core.config import settings
from .core.database import Base, SessionLocal, engine
from .core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from .models import ConnectionPin, Message, Pair, User, Media, DiaryMemory, CallSession
from .schemas.auth import ConnectByPin, UserCreate, UserLogin, PublicKeyUploadRequest
from .schemas.call import (
    CallInitiateRequest,
    CallRespondRequest,
    CallEndRequest,
    CallSignalRequest,
    CallSessionResponse,
)
from .schemas.message import EditMessageRequest, MessageCreate
from .schemas.media import MediaResponse, MediaUploadResponse
from .schemas.password import ChangePasswordRequest, ForgotPasswordRequest, ResetPasswordRequest
from .schemas.profile import ProfileUpdate
from .schemas.two_factor import (
    TwoFactorSetupResponse,
    TwoFactorEnableRequest,
    TwoFactorDisableRequest,
    TwoFactorVerifyLoginRequest,
    TwoFactorStatusResponse,
    Send2FAEmailRequest,
)
from .services.totp import (
    generate_totp_secret,
    get_totp_uri,
    verify_totp_code,
    generate_backup_codes,
    verify_and_consume_backup_code,
    hash_backup_code,
)
from .services.storage import (
    validate_file,
    save_upload_file,
    delete_physical_file,
    ensure_media_dirs,
)
from .services.email_service import (
    send_password_reset_email,
    send_2fa_otp_email,
)

from sqlalchemy import inspect

# Create tables
Base.metadata.create_all(bind=engine)
try:
    inspector = inspect(engine)
    with engine.connect() as conn:
        # Message columns
        if inspector.has_table("messages"):
            msg_cols = [c["name"] for c in inspector.get_columns("messages")]
            if "is_edited" not in msg_cols:
                conn.execute(text("ALTER TABLE messages ADD COLUMN is_edited BOOLEAN DEFAULT FALSE;"))
            if "nonce" not in msg_cols:
                conn.execute(text("ALTER TABLE messages ADD COLUMN nonce TEXT;"))
            if "is_encrypted" not in msg_cols:
                conn.execute(text("ALTER TABLE messages ADD COLUMN is_encrypted BOOLEAN DEFAULT FALSE;"))

        # User columns
        if inspector.has_table("users"):
            user_cols = [c["name"] for c in inspector.get_columns("users")]
            if "public_key" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN public_key TEXT;"))
            if "avatar_url" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN avatar_url TEXT;"))
            if "reset_otp" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN reset_otp TEXT;"))
            if "reset_otp_expires_at" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN reset_otp_expires_at TIMESTAMP;"))
            if "is_2fa_enabled" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN is_2fa_enabled BOOLEAN DEFAULT FALSE;"))
            if "two_factor_method" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN two_factor_method TEXT DEFAULT 'totp';"))
            if "totp_secret" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN totp_secret TEXT;"))
            if "backup_codes" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN backup_codes TEXT;"))
            if "email_2fa_otp" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN email_2fa_otp TEXT;"))
            if "email_2fa_expires_at" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN email_2fa_expires_at TIMESTAMP;"))
            if "last_seen" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN last_seen TIMESTAMP;"))

        # Media columns
        if inspector.has_table("media"):
            media_cols = [c["name"] for c in inspector.get_columns("media")]
            if "is_encrypted" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN is_encrypted BOOLEAN DEFAULT FALSE;"))
            if "is_view_once" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN is_view_once BOOLEAN DEFAULT FALSE;"))
            if "is_expired" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN is_expired BOOLEAN DEFAULT FALSE;"))
            if "viewed_at" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN viewed_at TIMESTAMP;"))
            if "encrypted_media_key" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN encrypted_media_key TEXT;"))
            if "encryption_nonce" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN encryption_nonce TEXT;"))
            if "ciphertext_hash" not in media_cols:
                conn.execute(text("ALTER TABLE media ADD COLUMN ciphertext_hash TEXT;"))
        conn.commit()
except Exception as e:
    print("Migration exception:", e)


def to_utc_iso(dt: Optional[datetime]) -> Optional[str]:
    """Ensures consistent ISO 8601 UTC timestamps with 'Z' suffix across all APIs."""
    if not dt:
        return None
    if dt.tzinfo is None:
        return dt.isoformat() + "Z"
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


app = FastAPI(
    title="TwoOfUs API",
    version="1.0.0"
)

# Enable CORS for cross-origin app requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("uploads/avatars", exist_ok=True)
os.makedirs("uploads/memories", exist_ok=True)
ensure_media_dirs()

app.mount(
    "/uploads",
    StaticFiles(directory="uploads"),
    name="uploads"
)


@app.get("/")
@app.get("/health")
@app.get("/ping")
def health_check():
    return {
        "status": "ok",
        "app": "TwoOfUs",
        "version": "1.0.0",
        "time": datetime.now(timezone.utc).isoformat()
    }


security = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    token = credentials.credentials
    payload = decode_access_token(token)

    if payload is None:
        print(f"[AUTH REJECTED]: Invalid or expired token: '{token}'")
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )

    return payload


def get_user_by_id(db: Session, user_id: int) -> User:
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def get_user_from_token_str(token: str, db: Session) -> User:
    payload = decode_access_token(token)
    if not payload or not payload.get("sub"):
        raise HTTPException(status_code=401, detail="Invalid token")
    user_id = int(payload["sub"])
    return get_user_by_id(db, user_id)


def verify_pair_access(db: Session, user1_id: int, user2_id: int) -> Optional[Pair]:
    if user1_id == user2_id:
        return None
    pair = db.query(Pair).filter(
        ((Pair.user1_id == user1_id) & (Pair.user2_id == user2_id)) |
        ((Pair.user1_id == user2_id) & (Pair.user2_id == user1_id))
    ).first()
    return pair


def verify_media_access(db: Session, media: Media, current_user_id: int):
    if media.sender_id == current_user_id or media.receiver_id == current_user_id:
        return
    if media.pair_id:
        pair = db.query(Pair).filter(Pair.id == media.pair_id).first()
        if pair and (pair.user1_id == current_user_id or pair.user2_id == current_user_id):
            return
    raise HTTPException(
        status_code=403,
        detail="Not authorized to access this media file"
    )


# ==========================
# Database Dependency
# ==========================
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ==========================
# PIN Generator
# ==========================
def generate_pin():
    chars = string.ascii_uppercase + string.digits
    return "".join(choices(chars, k=8))


# ==========================
# Root
# ==========================
@app.get("/")
def root():
    return {
        "message": "TwoOfUs Backend Running ❤️"
    }


# ==========================
# Register User
# ==========================
@app.post("/register")
def register_user(
    user: UserCreate,
    db: Session = Depends(get_db)
):
    email_clean = user.email.strip().lower()
    username_clean = user.username.strip()

    existing_email = (
        db.query(User)
        .filter(func.lower(User.email) == email_clean)
        .first()
    )

    if existing_email:
        raise HTTPException(
            status_code=400,
            detail="Email already exists"
        )

    existing_username = (
        db.query(User)
        .filter(func.lower(User.username) == username_clean.lower())
        .first()
    )

    if existing_username:
        raise HTTPException(
            status_code=400,
            detail="Username already exists"
        )

    new_user = User(
        email=email_clean,
        username=username_clean,
        password_hash=hash_password(user.password)
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "message": "User created successfully",
        "user_id": new_user.id
    }


# ==========================
# Login User
# ==========================
@app.post("/login")
def login(
    user: UserLogin,
    db: Session = Depends(get_db)
):
    login_input = user.email.strip()

    filter_condition = (
        (func.lower(User.email) == login_input.lower()) |
        (func.lower(User.username) == login_input.lower())
    )
    if login_input.isdigit():
        filter_condition = filter_condition | (User.id == int(login_input))

    existing_user = (
        db.query(User)
        .filter(filter_condition)
        .first()
    )

    if not existing_user:
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password"
        )

    if not verify_password(
        user.password,
        str(existing_user.password_hash)
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password"
        )

    if existing_user.is_2fa_enabled:
        temp_token = create_access_token(
            data={
                "sub": str(existing_user.id),
                "email": existing_user.email,
                "type": "2fa_pending"
            }
        )
        method = existing_user.two_factor_method or "totp"
        otp = None
        if method == "email":
            otp = "".join(choices(string.digits, k=6))
            existing_user.email_2fa_otp = otp
            existing_user.email_2fa_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
            db.commit()
            send_2fa_otp_email(to_email=str(existing_user.email), username=str(existing_user.username), code=otp)

        return {
            "requires_2fa": True,
            "two_factor_method": method,
            "temp_token": temp_token,
            "user_id": existing_user.id,
        }

    access_token = create_access_token(
        data={
            "sub": str(existing_user.id),
            "email": existing_user.email
        }
    )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": existing_user.id,
        "email": existing_user.email,
        "username": existing_user.username
    }


# ==========================
# Two-Factor Authentication (2FA)
# ==========================
@app.post("/2fa/setup", response_model=TwoFactorSetupResponse)
def setup_2fa(
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user = get_user_by_id(db, int(current_user["sub"]))
    secret = generate_totp_secret()
    otpauth_url = get_totp_uri(secret, str(user.email))
    plain_codes, _ = generate_backup_codes(count=8)

    return {
        "secret": secret,
        "otpauth_url": otpauth_url,
        "backup_codes": plain_codes,
        "email": user.email,
        "two_factor_method": user.two_factor_method or "totp"
    }


@app.post("/2fa/email/send-code")
def send_2fa_email_code(
    req: Optional[Send2FAEmailRequest] = None,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False)),
    db: Session = Depends(get_db)
):
    user = None
    # 1. Check temp_token in request body
    if req and req.temp_token and req.temp_token.strip():
        payload = decode_access_token(req.temp_token.strip())
        if payload and payload.get("sub"):
            user = db.query(User).filter(User.id == int(payload["sub"])).first()

    # 2. Check Authorization Bearer header
    if not user and credentials and credentials.credentials:
        payload = decode_access_token(credentials.credentials)
        if payload and payload.get("sub"):
            user = db.query(User).filter(User.id == int(payload["sub"])).first()

    if not user:
        raise HTTPException(
            status_code=401,
            detail="Authentication or valid 2FA temporary token required"
        )

    otp = "".join(choices(string.digits, k=6))
    user.email_2fa_otp = otp
    user.email_2fa_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    db.commit()

    # Dispatch email
    send_2fa_otp_email(to_email=str(user.email), username=str(user.username), code=otp)

    return {
        "message": f"Verification code sent to {user.email}",
        "email": user.email,
        "expires_in_seconds": 600,
    }


@app.post("/2fa/enable")
def enable_2fa(
    req: TwoFactorEnableRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user = get_user_by_id(db, int(current_user["sub"]))

    if req.method == "totp":
        if not req.secret or not verify_totp_code(req.secret, req.code):
            raise HTTPException(
                status_code=400,
                detail="Invalid 6-digit authenticator code. Check your Google Authenticator app and try again."
            )
        user.totp_secret = req.secret
        user.two_factor_method = "totp"
    elif req.method == "email":
        now = datetime.now(timezone.utc)
        if not user.email_2fa_otp or user.email_2fa_otp != req.code.strip():
            raise HTTPException(
                status_code=400,
                detail="Invalid email verification code. Please check your inbox or resend code."
            )
        if not user.email_2fa_expires_at:
            raise HTTPException(status_code=400, detail="Verification code has expired. Please request a new one.")
        
        expires_at = user.email_2fa_expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
            
        if now > expires_at:
            raise HTTPException(status_code=400, detail="Verification code has expired. Please request a new one.")

        user.email_2fa_otp = None
        user.email_2fa_expires_at = None
        user.two_factor_method = "email"
    else:
        raise HTTPException(status_code=400, detail="Invalid 2FA method")

    hashed_codes = [hash_backup_code(c) for c in req.backup_codes]
    user.backup_codes = json.dumps(hashed_codes)
    user.is_2fa_enabled = True
    db.commit()

    return {
        "message": f"Two-Factor Authentication ({req.method.upper()}) successfully enabled 🛡️"
    }


@app.post("/2fa/disable")
def disable_2fa(
    req: TwoFactorDisableRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user = get_user_by_id(db, int(current_user["sub"]))

    if not user.is_2fa_enabled:
        return {"message": "Two-Factor Authentication is already disabled"}

    is_verified = False
    if req.password and verify_password(req.password, str(user.password_hash)):
        is_verified = True
    elif req.code and user.totp_secret and verify_totp_code(str(user.totp_secret), req.code):
        is_verified = True
    elif req.code and user.email_2fa_otp and user.email_2fa_otp == req.code.strip():
        is_verified = True
    elif req.code and user.backup_codes:
        hashed_list = json.loads(str(user.backup_codes or "[]"))
        is_backup, _ = verify_and_consume_backup_code(req.code, hashed_list)
        if is_backup:
            is_verified = True

    if not is_verified:
        raise HTTPException(
            status_code=400,
            detail="Invalid password or verification code to disable 2FA"
        )

    user.is_2fa_enabled = False
    user.totp_secret = None
    user.email_2fa_otp = None
    user.email_2fa_expires_at = None
    user.backup_codes = None
    db.commit()

    return {
        "message": "Two-Factor Authentication disabled"
    }


@app.post("/2fa/verify-login")
def verify_2fa_login(
    req: TwoFactorVerifyLoginRequest,
    db: Session = Depends(get_db)
):
    payload = decode_access_token(req.temp_token)
    if not payload or payload.get("type") != "2fa_pending":
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired 2FA session token. Please log in again."
        )

    user_id = int(payload["sub"])
    user = get_user_by_id(db, user_id)

    if not user.is_2fa_enabled:
        raise HTTPException(
            status_code=400,
            detail="2FA is not enabled for this account"
        )

    code_clean = req.code.strip()
    is_valid = False

    # Check 6-digit TOTP
    if user.totp_secret and len(code_clean) == 6 and code_clean.isdigit():
        is_valid = verify_totp_code(str(user.totp_secret), code_clean)

    # Check Email OTP
    if not is_valid and user.email_2fa_otp and user.email_2fa_otp == code_clean:
        now = datetime.now(timezone.utc)
        expires_at = user.email_2fa_expires_at
        if expires_at:
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            if now <= expires_at:
                is_valid = True
                user.email_2fa_otp = None
                user.email_2fa_expires_at = None
                db.commit()

    # Check Backup recovery code
    if not is_valid and user.backup_codes:
        hashed_list = json.loads(str(user.backup_codes or "[]"))
        is_backup, updated_list = verify_and_consume_backup_code(code_clean, hashed_list)
        if is_backup:
            is_valid = True
            user.backup_codes = json.dumps(updated_list)
            db.commit()

    if not is_valid:
        raise HTTPException(
            status_code=401,
            detail="Invalid 6-digit code or backup recovery code"
        )

    access_token = create_access_token(
        data={
            "sub": str(user.id),
            "email": user.email
        }
    )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user.id,
        "email": user.email,
        "username": user.username
    }


@app.get("/2fa/status", response_model=TwoFactorStatusResponse)
def get_2fa_status(
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user = get_user_by_id(db, int(current_user["sub"]))
    codes = json.loads(str(user.backup_codes or "[]"))
    return {
        "is_2fa_enabled": bool(user.is_2fa_enabled),
        "two_factor_method": user.two_factor_method or "totp",
        "remaining_backup_codes": len(codes),
        "email": user.email
    }


# ==========================
# Forgot Password Request
# ==========================
@app.post("/forgot-password")
def forgot_password(
    data: ForgotPasswordRequest,
    db: Session = Depends(get_db)
):
    query_str = data.email_or_username.strip().lower()
    user = (
        db.query(User)
        .filter(
            (func.lower(User.email) == query_str) |
            (func.lower(User.username) == query_str)
        )
        .first()
    )
    if not user:
        raise HTTPException(
            status_code=404,
            detail="No account found with this email or username"
        )

    # Generate 6-digit cryptographic reset code
    code = ''.join(choices(string.digits, k=6))
    user.reset_otp = code
    user.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    db.commit()

    # Dispatch email
    send_password_reset_email(to_email=str(user.email), username=str(user.username), code=code)

    return {
        "message": f"Reset code sent to your registered email",
        "email": user.email,
        "username": user.username,
        "expires_in_minutes": 15,
    }


# ==========================
# Reset Password with Code
# ==========================
@app.post("/reset-password")
def reset_password(
    data: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    query_str = data.email_or_username.strip().lower()
    code_input = data.reset_code.strip()
    new_pwd = data.new_password.strip()

    if len(new_pwd) < 6:
        raise HTTPException(
            status_code=400,
            detail="New password must be at least 6 characters long"
        )

    user = (
        db.query(User)
        .filter(
            (func.lower(User.email) == query_str) |
            (func.lower(User.username) == query_str)
        )
        .first()
    )
    if not user:
        raise HTTPException(
            status_code=404,
            detail="No account found with this email or username"
        )

    if not user.reset_otp or user.reset_otp != code_input:
        raise HTTPException(
            status_code=400,
            detail="Invalid reset code. Please check and try again."
        )

    if user.reset_otp_expires_at:
        expires_at = user.reset_otp_expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) > expires_at:
            raise HTTPException(
                status_code=400,
                detail="Reset code has expired. Please request a new code."
            )

    # Update password and clear OTP
    user.password_hash = hash_password(new_pwd)
    user.reset_otp = None
    user.reset_otp_expires_at = None
    db.commit()

    return {
        "message": "Password reset successfully! You can now log in with your new password."
    }


# ==========================
# Generate Connection PIN
# ==========================
@app.get("/generate-pin/{user_id}")
def generate_connection_pin(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You can only generate PINs for yourself")

    user = (
        db.query(User)
        .filter(User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    pin = generate_pin()

    new_pin = ConnectionPin(
        user_id=user_id,
        pin_code=pin
    )

    db.add(new_pin)
    db.commit()
    db.refresh(new_pin)

    return {
        "user_id": user_id,
        "pin": pin
    }


# ==========================
# Connect By PIN
# ==========================
@app.post("/connect-by-pin")
def connect_by_pin(
    data: ConnectByPin,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != data.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You cannot pair on behalf of another user")

    joining_user = (
        db.query(User)
        .filter(User.id == data.user_id)
        .first()
    )

    if not joining_user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    pin_record = (
        db.query(ConnectionPin)
        .filter(ConnectionPin.pin_code == data.pin_code)
        .first()
    )

    if not pin_record:
        raise HTTPException(
            status_code=404,
            detail="Invalid PIN"
        )

    if pin_record.user_id == data.user_id:
        raise HTTPException(
            status_code=400,
            detail="You cannot connect to yourself"
        )

    existing_pair = (
        db.query(Pair)
        .filter(
            ((Pair.user1_id == pin_record.user_id) & (Pair.user2_id == data.user_id)) |
            ((Pair.user1_id == data.user_id) & (Pair.user2_id == pin_record.user_id))
        )
        .first()
    )

    if existing_pair:
        raise HTTPException(
            status_code=400,
            detail="Users already connected"
        )

    new_pair = Pair(
        user1_id=pin_record.user_id,
        user2_id=data.user_id,
        connection_pin=data.pin_code
    )

    db.add(new_pair)
    db.commit()
    db.refresh(new_pair)

    return {
        "message": "Connected successfully ❤️",
        "pair_id": new_pair.id,
        "user1_id": new_pair.user1_id,
        "user2_id": new_pair.user2_id
    }


@app.get("/users")
def get_users(
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    # Privacy restriction: Users can only see themselves and their connected partner
    pair = db.query(Pair).filter(
        (Pair.user1_id == auth_user_id) | (Pair.user2_id == auth_user_id)
    ).first()
    allowed_ids = {auth_user_id}
    if pair:
        allowed_ids.add(int(getattr(pair, "user1_id")))
        allowed_ids.add(int(getattr(pair, "user2_id")))

    users = db.query(User).filter(User.id.in_(allowed_ids)).all()

    return [
        {
            "id": user.id,
            "email": user.email,
            "username": user.username
        }
        for user in users
    ]


@app.get("/pairs")
def get_pairs(
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    pairs = db.query(Pair).filter(
        (Pair.user1_id == auth_user_id) | (Pair.user2_id == auth_user_id)
    ).all()

    return [
        {
            "id": pair.id,
            "user1_id": pair.user1_id,
            "user2_id": pair.user2_id
        }
        for pair in pairs
    ]


@app.get("/pair-status/{user_id}")
def pair_status(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You can only check your own pair status")

    pair = (
        db.query(Pair)
        .filter(
            (Pair.user1_id == user_id) |
            (Pair.user2_id == user_id)
        )
        .first()
    )

    if not pair:
        return {
            "connected": False
        }

    partner_id = (
        pair.user2_id
        if pair.user1_id == user_id
        else pair.user1_id
    )

    partner = (
        db.query(User)
        .filter(User.id == partner_id)
        .first()
    )

    if not partner:
        return {
            "connected": False
        }

    return {
        "connected": True,
        "partner_id": partner.id,
        "partner_name": partner.username,
        "partner_email": partner.email
    }


# ==========================
# Health Check
# ==========================
@app.get("/health")
def health():
    return {
        "status": "ok"
    }


@app.get("/me")
def get_me(
    current_user = Depends(get_current_user)
):
    return {
        "user": current_user
    }


# ==========================
# Media Upload & Management
# ==========================
@app.post("/media/upload", response_model=List[MediaUploadResponse])
async def upload_media(
    receiver_id: int = Form(...),
    is_encrypted: Optional[str] = Form(None),
    is_view_once: Optional[str] = Form(None),
    encrypted_media_key: Optional[str] = Form(None),
    encryption_nonce: Optional[str] = Form(None),
    ciphertext_hash: Optional[str] = Form(None),
    files: List[UploadFile] = File(...),
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    sender_id = int(current_user_payload.get("sub"))
    receiver = db.query(User).filter(User.id == receiver_id).first()
    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver user not found")

    pair = verify_pair_access(db, sender_id, receiver_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You can only upload and share media with your paired partner")
    pair_id = pair.id

    is_enc_bool = is_encrypted.lower() in ("true", "1") if is_encrypted is not None else False
    is_vo_bool = is_view_once.lower() in ("true", "1") if is_view_once is not None else False

    responses = []
    for file in files:
        file.file.seek(0, os.SEEK_END)
        file_size = file.file.tell()
        file.file.seek(0)

        media_type, ext = validate_file(file, file_size)
        stored_filename, storage_path, thumbnail_path, width, height = save_upload_file(
            file, media_type, ext, is_encrypted=is_enc_bool
        )

        sanitized_filename = f"enc_{stored_filename}" if is_enc_bool else (file.filename or f"attachment{ext}")

        media_record = Media(
            sender_id=sender_id,
            receiver_id=receiver_id,
            pair_id=pair_id,
            original_filename=sanitized_filename,
            stored_filename=stored_filename,
            media_type=media_type,
            mime_type=file.content_type or "application/octet-stream",
            file_size=file_size,
            storage_path=storage_path,
            thumbnail_path=thumbnail_path,
            width=width,
            height=height,
            is_encrypted=is_enc_bool,
            is_view_once=is_vo_bool,
            is_expired=False,
            encrypted_media_key=encrypted_media_key,
            encryption_nonce=encryption_nonce,
            ciphertext_hash=ciphertext_hash
        )
        db.add(media_record)
        db.commit()
        db.refresh(media_record)

        responses.append(MediaUploadResponse(
            media_id=int(str(media_record.id)),
            original_filename=str(media_record.original_filename),
            stored_filename=str(media_record.stored_filename),
            media_type=str(media_record.media_type),
            mime_type=str(media_record.mime_type),
            file_size=int(str(media_record.file_size)),
            storage_path=str(media_record.storage_path),
            thumbnail_path=str(media_record.thumbnail_path) if media_record.thumbnail_path else None,
            is_view_once=is_vo_bool
        ))

    return responses


# ==========================
# E2EE Public Key Management
# ==========================
@app.post("/keys/public")
def upload_public_key(
    data: PublicKeyUploadRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.public_key = data.public_key
    db.commit()
    return {"message": "Public key updated successfully", "user_id": user_id}


@app.get("/keys/{user_id}")
def get_user_public_key(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        pair = verify_pair_access(db, auth_user_id, user_id)
        if not pair:
            raise HTTPException(status_code=403, detail="Forbidden: Not authorized to fetch this public key")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "user_id": user.id,
        "public_key": user.public_key
    }


@app.post("/send-message")
def send_message(
    data: MessageCreate,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != data.sender_id:
        raise HTTPException(status_code=403, detail="Forbidden: Sender ID does not match authenticated user")

    pair = verify_pair_access(db, data.sender_id, data.receiver_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You can only message your connected partner")

    message = Message(
        sender_id=data.sender_id,
        receiver_id=data.receiver_id,
        content=data.content,
        nonce=data.nonce,
        is_encrypted=data.is_encrypted if data.is_encrypted is not None else False
    )

    db.add(message)
    db.commit()
    db.refresh(message)

    attached_media = []
    if data.media_ids:
        pair_id = pair.id if pair else None

        for m_id in data.media_ids:
            media_item = db.query(Media).filter(Media.id == m_id, Media.sender_id == data.sender_id).first()
            if media_item:
                media_item.message_id = message.id
                if pair_id:
                    media_item.pair_id = pair_id
                attached_media.append(media_item)
        db.commit()

    return {
        "message_id": message.id,
        "status": "sent",
        "media": [
            {
                "id": m.id,
                "original_filename": m.original_filename,
                "stored_filename": m.stored_filename,
                "media_type": m.media_type,
                "mime_type": m.mime_type,
                "file_size": m.file_size,
                "storage_path": m.storage_path,
                "thumbnail_path": m.thumbnail_path,
                "created_at": str(m.created_at)
            } for m in attached_media
        ]
    }


@app.get("/messages/{user1}/{user2}")
def get_messages(
    user1: int,
    user2: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id not in (user1, user2):
        raise HTTPException(status_code=403, detail="Forbidden: Not authorized to access this conversation")

    pair = verify_pair_access(db, user1, user2)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: Conversation access restricted to paired partners")

    # Auto-sync any call sessions that ended but don't have a chat log yet
    past_calls = (
        db.query(CallSession)
        .filter(
            ((CallSession.caller_id == user1) & (CallSession.receiver_id == user2)) |
            ((CallSession.caller_id == user2) & (CallSession.receiver_id == user1))
        )
        .filter(CallSession.status.in_(["ended", "rejected", "missed"]))
        .all()
    )
    for pc in past_calls:
        existing_log = (
            db.query(Message)
            .filter(
                ((Message.sender_id == pc.caller_id) & (Message.receiver_id == pc.receiver_id)) |
                ((Message.sender_id == pc.receiver_id) & (Message.receiver_id == pc.caller_id))
            )
            .filter(Message.content.like(f'CALL_LOG:%"call_id": {pc.id}%'))
            .first()
        )
        if not existing_log:
            _create_call_log_message(db, pc)

    messages = (
        db.query(Message)
        .filter(
            (
                (Message.sender_id == user1) &
                (Message.receiver_id == user2)
            )
            |
            (
                (Message.sender_id == user2) &
                (Message.receiver_id == user1)
            )
        )
        .order_by(Message.created_at.asc())
        .all()
    )

    result = []
    for m in messages:
        attached_media = (
            db.query(Media)
            .filter(Media.message_id == m.id)
            .all()
        )
        result.append({
            "id": m.id,
            "sender_id": m.sender_id,
            "receiver_id": m.receiver_id,
            "content": m.content,
            "nonce": m.nonce,
            "is_encrypted": m.is_encrypted if m.is_encrypted is not None else False,
            "is_edited": m.is_edited if m.is_edited is not None else False,
            "created_at": to_utc_iso(m.created_at),
            "media": [
                {
                    "id": med.id,
                    "sender_id": med.sender_id,
                    "receiver_id": med.receiver_id,
                    "original_filename": med.original_filename,
                    "stored_filename": med.stored_filename,
                    "media_type": med.media_type,
                    "mime_type": med.mime_type,
                    "file_size": med.file_size,
                    "storage_path": med.storage_path,
                    "thumbnail_path": med.thumbnail_path,
                    "is_encrypted": med.is_encrypted if med.is_encrypted is not None else False,
                    "is_view_once": med.is_view_once if med.is_view_once is not None else False,
                    "is_expired": med.is_expired if med.is_expired is not None else False,
                    "viewed_at": to_utc_iso(med.viewed_at) if med.viewed_at else None,
                    "encrypted_media_key": med.encrypted_media_key,
                    "encryption_nonce": med.encryption_nonce,
                    "created_at": to_utc_iso(med.created_at)
                } for med in attached_media
            ]
        })

    return result


@app.delete("/messages/{message_id}")
def delete_message(
    message_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    message = (
        db.query(Message)
        .filter(Message.id == message_id)
        .first()
    )

    if not message:
        raise HTTPException(
            status_code=404,
            detail="Message not found"
        )

    if message.sender_id != auth_user_id and message.receiver_id != auth_user_id:
        raise HTTPException(
            status_code=403,
            detail="Forbidden: You can only delete messages in your own conversation"
        )

    # If this message is a CALL_LOG, also remove the underlying CallSession record so it is not re-created
    if message.content and str(message.content).startswith("CALL_LOG:"):
        try:
            raw = str(message.content)[len("CALL_LOG:"):]
            data = json.loads(raw)
            call_id = data.get("call_id")
            if call_id:
                db.query(CallSession).filter(CallSession.id == int(call_id)).delete()
        except Exception:
            pass

    # Clean up physical storage files for all associated media
    attached_media = db.query(Media).filter(Media.message_id == message_id).all()
    for m in attached_media:
        delete_physical_file(str(m.storage_path), str(m.thumbnail_path) if m.thumbnail_path else None)
        db.delete(m)

    db.delete(message)
    db.commit()

    return {
        "message": "Deleted"
    }


@app.delete("/messages/conversation/{partner_id}")
def clear_conversation_messages(
    partner_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    pair = verify_pair_access(db, auth_user_id, partner_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You can only clear messages with your paired partner")

    messages = (
        db.query(Message)
        .filter(
            ((Message.sender_id == auth_user_id) & (Message.receiver_id == partner_id)) |
            ((Message.sender_id == partner_id) & (Message.receiver_id == auth_user_id))
        )
        .all()
    )

    for msg in messages:
        attached_media = db.query(Media).filter(Media.message_id == msg.id).all()
        for m in attached_media:
            delete_physical_file(str(m.storage_path), str(m.thumbnail_path) if m.thumbnail_path else None)
            db.delete(m)
        db.delete(msg)

    # Also clear call sessions between this pair
    db.query(CallSession).filter(
        ((CallSession.caller_id == auth_user_id) & (CallSession.receiver_id == partner_id)) |
        ((CallSession.caller_id == partner_id) & (CallSession.receiver_id == auth_user_id))
    ).delete()

    db.commit()
    return {
        "message": "Conversation cleared successfully",
        "deleted_count": len(messages)
    }


@app.delete("/call/history/{partner_id}")
def clear_call_history(
    partner_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    pair = verify_pair_access(db, auth_user_id, partner_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You can only clear call history with your paired partner")

    call_logs = (
        db.query(Message)
        .filter(
            ((Message.sender_id == auth_user_id) & (Message.receiver_id == partner_id)) |
            ((Message.sender_id == partner_id) & (Message.receiver_id == auth_user_id))
        )
        .filter(Message.content.like("CALL_LOG:%"))
        .all()
    )
    for msg in call_logs:
        db.delete(msg)

    db.query(CallSession).filter(
        ((CallSession.caller_id == auth_user_id) & (CallSession.receiver_id == partner_id)) |
        ((CallSession.caller_id == partner_id) & (CallSession.receiver_id == auth_user_id))
    ).delete()

    db.commit()
    return {
        "message": "Call history cleared successfully",
        "deleted_count": len(call_logs)
    }


# ==========================
# Secure Media Access Endpoints
# ==========================
@app.get("/media/{media_id}")
def get_media_info(
    media_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    media = db.query(Media).filter(Media.id == media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")

    verify_media_access(db, media, user_id)

    # Server-side View Once expiration enforcement
    if media.is_view_once and (media.is_expired or not os.path.exists(str(media.storage_path))):
        raise HTTPException(
            status_code=410,
            detail="This View Once media has expired and has been securely purged."
        )

    return media


@app.get("/media/{media_id}/file")
def download_media_file(
    media_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    media = db.query(Media).filter(Media.id == media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")

    verify_media_access(db, media, user_id)

    storage_p = str(media.storage_path)

    # Server-side View Once atomic single-use consumption with race-condition prevention
    if media.is_view_once:
        # Atomic DB lock & conditional update
        rows_updated = db.query(Media).filter(
            Media.id == media_id,
            Media.is_expired == False
        ).update({
            "is_expired": True,
            "viewed_at": datetime.now(timezone.utc)
        })
        db.commit()

        if rows_updated == 0 or not os.path.exists(storage_p):
            raise HTTPException(
                status_code=410,
                detail="This View Once media has expired and has been securely purged."
            )

        try:
            with open(storage_p, "rb") as f:
                content_bytes = f.read()
        except Exception:
            raise HTTPException(status_code=500, detail="Failed to read media payload")

        # Shred physical files from disk immediately
        delete_physical_file(storage_p, str(media.thumbnail_path) if media.thumbnail_path else None)

        from fastapi.responses import Response
        return Response(
            content=content_bytes,
            media_type=str(media.mime_type),
            headers={
                "Content-Disposition": f'attachment; filename="{media.original_filename}"',
                "X-View-Once": "true",
                "X-View-Once-Consumed": "true",
            }
        )

    if not os.path.exists(storage_p):
        raise HTTPException(status_code=404, detail="Physical media file not found")

    return FileResponse(
        path=storage_p,
        media_type=str(media.mime_type),
        filename=str(media.original_filename)
    )


@app.get("/media/{media_id}/thumbnail")
def download_media_thumbnail(
    media_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    media = db.query(Media).filter(Media.id == media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")

    verify_media_access(db, media, user_id)

    if media.is_view_once and (media.is_expired or not os.path.exists(str(media.storage_path))):
        raise HTTPException(
            status_code=410,
            detail="This View Once media has expired and has been securely purged."
        )

    thumb_p = str(media.thumbnail_path) if media.thumbnail_path else None
    target_path = thumb_p if (thumb_p and os.path.exists(thumb_p)) else str(media.storage_path)

    if not os.path.exists(target_path):
        raise HTTPException(status_code=404, detail="Thumbnail file not found")

    return FileResponse(
        path=target_path,
        media_type="image/jpeg" if media.thumbnail_path else str(media.mime_type)
    )


@app.get("/media/pair/{partner_id}")
def get_pair_media(
    partner_id: int,
    media_type: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    pair = verify_pair_access(db, user_id, partner_id)

    query = db.query(Media).filter(
        ((Media.sender_id == user_id) & (Media.receiver_id == partner_id)) |
        ((Media.sender_id == partner_id) & (Media.receiver_id == user_id))
    )

    if media_type:
        query = query.filter(Media.media_type == media_type)

    media_list = query.order_by(Media.created_at.desc()).offset(offset).limit(limit).all()

    return [
        {
            "id": m.id,
            "message_id": m.message_id,
            "sender_id": m.sender_id,
            "receiver_id": m.receiver_id,
            "original_filename": m.original_filename,
            "stored_filename": m.stored_filename,
            "media_type": m.media_type,
            "mime_type": m.mime_type,
            "file_size": m.file_size,
            "is_encrypted": m.is_encrypted if m.is_encrypted is not None else False,
            "is_view_once": m.is_view_once if m.is_view_once is not None else False,
            "is_expired": m.is_expired if m.is_expired is not None else False,
            "viewed_at": str(m.viewed_at) if m.viewed_at else None,
            "encrypted_media_key": m.encrypted_media_key,
            "encryption_nonce": m.encryption_nonce,
            "created_at": str(m.created_at)
        } for m in media_list
    ]


@app.post("/admin/cleanup-orphans")
def manual_cleanup_orphans(
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    from .services.cleanup import cleanup_orphaned_media_files
    result = cleanup_orphaned_media_files(db)
    return result


@app.delete("/media/{media_id}")
def delete_single_media(
    media_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    media = db.query(Media).filter(Media.id == media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")

    if media.sender_id != user_id:
        raise HTTPException(status_code=403, detail="Only sender can delete this media file")

    delete_physical_file(str(media.storage_path), str(media.thumbnail_path) if media.thumbnail_path else None)
    db.delete(media)
    db.commit()

    return {"message": "Media deleted successfully"}


@app.put("/messages/{message_id}")
def edit_message(
    message_id: int,
    data: EditMessageRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    msg = (
        db.query(Message)
        .filter(Message.id == message_id)
        .first()
    )

    if not msg:
        raise HTTPException(
            status_code=404,
            detail="Message not found",
        )

    if msg.sender_id != auth_user_id:
        raise HTTPException(
            status_code=403,
            detail="Forbidden: Only the message sender can edit this message",
        )

    # 15-minute window check (900 seconds)
    if msg.created_at:
        now = datetime.now(timezone.utc)
        created_at = msg.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        elapsed = (now - created_at).total_seconds()
        if elapsed > 900:
            raise HTTPException(
                status_code=400,
                detail="Messages can only be edited within 15 minutes of sending",
            )

    msg.content = data.content
    if data.nonce is not None:
        msg.nonce = data.nonce
    if data.is_encrypted is not None:
        msg.is_encrypted = data.is_encrypted
    msg.is_edited = True

    db.commit()
    db.refresh(msg)

    return {
        "success": True,
        "message": "Updated",
        "is_edited": True,
    }


# Real-time in-memory presence and typing trackers
user_last_heartbeat: Dict[int, datetime] = {}
user_typing_status: Dict[int, Dict[str, Any]] = {}  # {user_id: {"target_id": partner_id, "timestamp": datetime}}


class TypingStatusRequest(BaseModel):
    partner_id: int
    is_typing: bool


@app.post("/heartbeat")
def heartbeat(
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    now = datetime.now(timezone.utc)
    user_last_heartbeat[user_id] = now
    user = db.query(User).filter(User.id == user_id).first()
    if user:
        user.last_seen = now
        db.commit()
    return {"status": "ok", "timestamp": to_utc_iso(now)}


@app.post("/presence/offline")
def set_offline(
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    user_last_heartbeat.pop(user_id, None)
    user_typing_status.pop(user_id, None)
    user = db.query(User).filter(User.id == user_id).first()
    if user:
        user.last_seen = datetime.now(timezone.utc) - timedelta(seconds=120)
        db.commit()
    return {"status": "offline"}


@app.post("/typing")
def update_typing_status(
    data: TypingStatusRequest,
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    now = datetime.now(timezone.utc)
    if data.is_typing:
        user_typing_status[user_id] = {
            "target_id": data.partner_id,
            "timestamp": now,
        }
    else:
        user_typing_status.pop(user_id, None)
    return {"status": "ok"}


@app.get("/user/{user_id}/status")
def get_user_online_status(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        pair = verify_pair_access(db, auth_user_id, user_id)
        if not pair:
            raise HTTPException(status_code=403, detail="Forbidden: Not authorized to view user status")

    target_user = db.query(User).filter(User.id == user_id).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    now = datetime.now(timezone.utc)
    is_online = False

    # Check high-speed in-memory heartbeat tracker first
    if user_id in user_last_heartbeat:
        diff = (now - user_last_heartbeat[user_id]).total_seconds()
        if diff <= 4.0:
            is_online = True
        else:
            user_last_heartbeat.pop(user_id, None)
    elif target_user.last_seen:
        last_seen_utc = target_user.last_seen if target_user.last_seen.tzinfo else target_user.last_seen.replace(tzinfo=timezone.utc)
        diff = (now - last_seen_utc).total_seconds()
        if diff <= 4.0:
            is_online = True

    # Check typing status
    is_typing = False
    if user_id in user_typing_status:
        typing_data = user_typing_status[user_id]
        if typing_data.get("target_id") == auth_user_id:
            diff_typing = (now - typing_data["timestamp"]).total_seconds()
            if diff_typing <= 3.5:
                is_typing = True
            else:
                user_typing_status.pop(user_id, None)

    return {
        "user_id": target_user.id,
        "is_online": is_online,
        "is_typing": is_typing,
        "last_seen": to_utc_iso(target_user.last_seen)
    }


@app.get("/profile/{user_id}")
def get_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        pair = verify_pair_access(db, auth_user_id, user_id)
        if not pair:
            raise HTTPException(status_code=403, detail="Forbidden: Not authorized to view this profile")

    user = (
        db.query(User)
        .filter(User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    is_online = False
    if user.last_seen:
        last_seen_utc = user.last_seen if user.last_seen.tzinfo else user.last_seen.replace(tzinfo=timezone.utc)
        diff = (datetime.now(timezone.utc) - last_seen_utc).total_seconds()
        if diff <= 45:
            is_online = True

    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "bio": user.bio,
        "birthday": user.birthday,
        "avatar_url": user.avatar_url,
        "is_online": is_online,
        "last_seen": user.last_seen.isoformat() if user.last_seen else None
    }


@app.put("/profile/{user_id}")
def update_profile(
    user_id: int,
    data: ProfileUpdate,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You can only update your own profile")

    user = (
        db.query(User)
        .filter(User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    existing_username = (
        db.query(User)
        .filter(
            func.lower(User.username) == data.username.strip().lower(),
            User.id != user_id
        )
        .first()
    )

    if existing_username:
        raise HTTPException(
            status_code=400,
            detail="Username already taken"
        )

    user.username = data.username.strip()
    user.bio = data.bio
    user.birthday = data.birthday

    db.commit()
    db.refresh(user)

    return {
        "message": "Profile updated",
        "username": user.username,
        "bio": user.bio,
        "birthday": user.birthday
    }


@app.post("/profile/avatar/{user_id}")
def upload_avatar(
    user_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You can only update your own avatar")

    user = (
        db.query(User)
        .filter(User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    # Validate file extension and size to prevent path traversal or malicious uploads
    filename = file.filename or "avatar.jpg"
    ext = os.path.splitext(filename)[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
        raise HTTPException(status_code=415, detail="Only JPG, PNG, and WebP avatar images are supported")

    file.file.seek(0, os.SEEK_END)
    file_size = file.file.tell()
    file.file.seek(0)
    if file_size > 5 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Avatar image exceeds maximum size of 5 MB")

    os.makedirs("uploads/avatars", exist_ok=True)
    file_path = f"uploads/avatars/{user_id}{ext}"

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    user.avatar_url = file_path
    db.commit()

    return {
        "avatar_url": file_path
    }


@app.put("/change-password/{user_id}")
def change_password(
    user_id: int,
    data: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You can only change your own password")

    user = (
        db.query(User)
        .filter(User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    if not verify_password(
        data.current_password,
        str(user.password_hash),
    ):
        raise HTTPException(
            status_code=401,
            detail="Current password is incorrect",
        )

    user.password_hash = hash_password(
        data.new_password
    )

    db.commit()

    return {
        "message": "Password changed successfully"
    }


# =============================================================================
# DIARY & MEMORY PHOTO GALLERY ENDPOINTS
# =============================================================================

@app.get("/memories/pair/{partner_id}")
def get_pair_memories(
    partner_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    pair = verify_pair_access(db, user_id, partner_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You are not paired with this user")

    memories = (
        db.query(DiaryMemory)
        .filter(
            ((DiaryMemory.sender_id == user_id) & (DiaryMemory.receiver_id == partner_id)) |
            ((DiaryMemory.sender_id == partner_id) & (DiaryMemory.receiver_id == user_id))
        )
        .order_by(DiaryMemory.entry_date.desc(), DiaryMemory.created_at.desc())
        .all()
    )

    return [
        {
            "id": m.id,
            "sender_id": m.sender_id,
            "receiver_id": m.receiver_id,
            "entry_date": m.entry_date,
            "content": m.content,
            "mood_emoji": m.mood_emoji,
            "image_url": m.image_url,
            "created_at": m.created_at.isoformat() if m.created_at else None
        }
        for m in memories
    ]


@app.post("/memories/create")
def create_memory_entry(
    partner_id: int = Form(...),
    entry_date: str = Form(...),
    content: str = Form(""),
    mood_emoji: Optional[str] = Form(None),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    pair = verify_pair_access(db, user_id, partner_id)
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You are not paired with this user")

    image_url = None
    if photo and photo.filename:
        filename = photo.filename
        ext = os.path.splitext(filename)[1].lower()
        if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
            raise HTTPException(status_code=415, detail="Only JPG, PNG, and WebP images are supported for diary memories")

        photo.file.seek(0, os.SEEK_END)
        photo_size = photo.file.tell()
        photo.file.seek(0)
        if photo_size > settings.MAX_IMAGE_SIZE_BYTES:
            raise HTTPException(status_code=413, detail=f"Image size exceeds maximum allowed limit of {settings.MAX_IMAGE_SIZE_BYTES // (1024*1024)}MB")

        os.makedirs("uploads/memories", exist_ok=True)
        unique_name = f"{user_id}_{int(datetime.now(timezone.utc).timestamp())}_{''.join(choices(string.ascii_lowercase + string.digits, k=6))}{ext}"
        saved_path = os.path.join("uploads", "memories", unique_name)
        with open(saved_path, "wb") as buffer:
            shutil.copyfileobj(photo.file, buffer)
        image_url = f"uploads/memories/{unique_name}"

    entry = DiaryMemory(
        sender_id=user_id,
        receiver_id=partner_id,
        entry_date=entry_date.strip(),
        content=content.strip(),
        mood_emoji=mood_emoji.strip() if mood_emoji else None,
        image_url=image_url
    )

    db.add(entry)
    db.commit()
    db.refresh(entry)

    return {
        "id": entry.id,
        "sender_id": entry.sender_id,
        "receiver_id": entry.receiver_id,
        "entry_date": entry.entry_date,
        "content": entry.content,
        "mood_emoji": entry.mood_emoji,
        "image_url": entry.image_url,
        "created_at": entry.created_at.isoformat() if entry.created_at else None
    }


@app.delete("/memories/{memory_id}")
def delete_memory_entry(
    memory_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    entry = db.query(DiaryMemory).filter(DiaryMemory.id == memory_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Memory entry not found")

    if entry.sender_id != user_id and entry.receiver_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: You cannot delete this entry")

    if entry.image_url:
        img_path = str(entry.image_url)
        if os.path.exists(img_path):
            try:
                os.remove(img_path)
            except Exception:
                pass

    db.delete(entry)
    db.commit()

    return {"message": "Memory deleted successfully", "id": memory_id}


# ============================================================================
# VOICE & VIDEO CALL SIGNALING SUBSYSTEM
# ============================================================================

class CallConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)

    def disconnect(self, user_id: int, websocket: WebSocket):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def send_to_user(self, user_id: int, message: dict):
        if user_id in self.active_connections:
            dead_sockets = []
            for ws in self.active_connections[user_id]:
                try:
                    await ws.send_json(message)
                except Exception:
                    dead_sockets.append(ws)
            for ws in dead_sockets:
                self.disconnect(user_id, ws)

call_manager = CallConnectionManager()


@app.websocket("/ws/call/{user_id}")
async def call_websocket_endpoint(websocket: WebSocket, user_id: int):
    await call_manager.connect(user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")
            target_user_id = data.get("target_user_id")

            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif target_user_id:
                # Forward WebRTC signaling (offer/answer/ice/status) to target partner
                await call_manager.send_to_user(int(target_user_id), data)
    except WebSocketDisconnect:
        call_manager.disconnect(user_id, websocket)
    except Exception:
        call_manager.disconnect(user_id, websocket)


@app.post("/call/initiate", response_model=CallSessionResponse)
async def initiate_call(
    data: CallInitiateRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    caller_id = int(current_user_payload.get("sub"))
    receiver_id = data.receiver_id

    # Verify pairing
    pair = (
        db.query(Pair)
        .filter(
            ((Pair.user1_id == caller_id) & (Pair.user2_id == receiver_id)) |
            ((Pair.user1_id == receiver_id) & (Pair.user2_id == caller_id))
        )
        .first()
    )
    if not pair:
        raise HTTPException(status_code=403, detail="Forbidden: You can only call your paired partner")

    # Cancel any previous hanging ringing calls
    prev_calls = (
        db.query(CallSession)
        .filter(
            (CallSession.status == "ringing") &
            (((CallSession.caller_id == caller_id) & (CallSession.receiver_id == receiver_id)) |
             ((CallSession.caller_id == receiver_id) & (CallSession.receiver_id == caller_id)))
        )
        .all()
    )
    for c in prev_calls:
        c.status = "missed"
        c.ended_at = datetime.now(timezone.utc)

    session = CallSession(
        caller_id=caller_id,
        receiver_id=receiver_id,
        call_type=data.call_type,
        status="ringing",
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # Dispatch real-time WebSocket incoming call notification
    caller_user = db.query(User).filter(User.id == caller_id).first()
    caller_name = caller_user.username if caller_user else "Partner"

    await call_manager.send_to_user(
        receiver_id,
        {
            "type": "incoming_call",
            "call_id": session.id,
            "caller_id": caller_id,
            "caller_name": caller_name,
            "call_type": session.call_type,
            "created_at": session.created_at.isoformat() if session.created_at else None,
        }
    )

    return session


def _create_call_log_message(db: Session, session: CallSession):
    import json
    try:
        caller_id = int(getattr(session, "caller_id"))
        receiver_id = int(getattr(session, "receiver_id"))
        call_id = int(getattr(session, "id"))
        call_type = str(getattr(session, "call_type"))
        status = str(getattr(session, "status"))
        duration_seconds = int(getattr(session, "duration_seconds", 0))

        call_payload = {
            "call_id": call_id,
            "caller_id": caller_id,
            "receiver_id": receiver_id,
            "call_type": call_type,
            "status": status,
            "duration_seconds": duration_seconds,
            "ended_at": to_utc_iso(session.ended_at) if session.ended_at else to_utc_iso(datetime.now(timezone.utc))
        }
        content_str = f"CALL_LOG:{json.dumps(call_payload)}"
        msg = Message(
            sender_id=caller_id,
            receiver_id=receiver_id,
            content=content_str,
            is_encrypted=False,
            created_at=datetime.now(timezone.utc)
        )
        db.add(msg)
        db.commit()
    except Exception as e:
        print("Error logging call message:", e)


@app.post("/call/respond", response_model=CallSessionResponse)
async def respond_to_call(
    data: CallRespondRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    session = db.query(CallSession).filter(CallSession.id == data.call_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Call session not found")

    caller_id = int(getattr(session, "caller_id"))
    receiver_id = int(getattr(session, "receiver_id"))
    if receiver_id != user_id and caller_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: Not a participant in this call")

    now = datetime.now(timezone.utc)
    if data.action == "accept":
        setattr(session, "status", "ongoing")
        session.started_at = now
        db.commit()
        db.refresh(session)

        # Notify caller that call was accepted
        await call_manager.send_to_user(
            caller_id,
            {
                "type": "call_accepted",
                "call_id": session.id,
                "started_at": session.started_at.isoformat() if session.started_at else None,
            }
        )
    elif data.action == "reject":
        setattr(session, "status", "rejected")
        session.ended_at = now
        db.commit()
        db.refresh(session)

        # Create call log message in chat history
        _create_call_log_message(db, session)

        # Notify caller that call was rejected
        await call_manager.send_to_user(
            caller_id,
            {
                "type": "call_rejected",
                "call_id": session.id,
            }
        )
    else:
        raise HTTPException(status_code=400, detail="Invalid action. Must be 'accept' or 'reject'")

    return session


@app.post("/call/end", response_model=CallSessionResponse)
async def end_call(
    data: CallEndRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    session = db.query(CallSession).filter(CallSession.id == data.call_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Call session not found")

    caller_id = int(getattr(session, "caller_id"))
    receiver_id = int(getattr(session, "receiver_id"))
    if caller_id != user_id and receiver_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: Not a participant in this call")

    now = datetime.now(timezone.utc)
    current_status = str(getattr(session, "status", ""))
    if current_status != "ended":
        if current_status == "ringing":
            setattr(session, "status", "missed" if user_id == caller_id else "rejected")
        else:
            setattr(session, "status", "ended")

        session.ended_at = now
        if session.started_at:
            started = session.started_at
            if started.tzinfo is None:
                started = started.replace(tzinfo=timezone.utc)
            duration = int((now - started).total_seconds())
            session.duration_seconds = max(0, duration)

        db.commit()
        db.refresh(session)

        # Create call log message in chat history
        _create_call_log_message(db, session)

    # Notify other participant
    other_party_id = receiver_id if user_id == caller_id else caller_id
    await call_manager.send_to_user(
        other_party_id,
        {
            "type": "call_ended",
            "call_id": session.id,
            "duration_seconds": session.duration_seconds,
            "status": str(getattr(session, "status", "ended")),
        }
    )

    return session


@app.post("/call/signal")
async def send_call_signal(
    data: CallSignalRequest,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    session = db.query(CallSession).filter(CallSession.id == data.call_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Call session not found")

    if session.caller_id != user_id and session.receiver_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden: Not a participant in this call")

    await call_manager.send_to_user(
        data.target_user_id,
        {
            "type": data.signal_type,
            "call_id": data.call_id,
            "sender_id": user_id,
            "payload": data.payload,
        }
    )

    return {"status": "signal_dispatched"}


@app.get("/call/active/{user_id}", response_model=Optional[CallSessionResponse])
def get_active_call_for_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    auth_user_id = int(current_user_payload.get("sub"))
    if auth_user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    active_session = (
        db.query(CallSession)
        .filter(
            (CallSession.status.in_(["ringing", "ongoing"])) &
            ((CallSession.caller_id == user_id) | (CallSession.receiver_id == user_id))
        )
        .order_by(CallSession.id.desc())
        .first()
    )

    return active_session


@app.get("/call/history/{partner_id}", response_model=List[CallSessionResponse])
def get_call_history(
    partner_id: int,
    db: Session = Depends(get_db),
    current_user_payload = Depends(get_current_user)
):
    user_id = int(current_user_payload.get("sub"))
    history = (
        db.query(CallSession)
        .filter(
            ((CallSession.caller_id == user_id) & (CallSession.receiver_id == partner_id)) |
            ((CallSession.caller_id == partner_id) & (CallSession.receiver_id == user_id))
        )
        .order_by(CallSession.created_at.desc())
        .limit(50)
        .all()
    )
    return history