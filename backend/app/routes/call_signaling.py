import base64
import hashlib
import hmac
import os
import time
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from ..core.database import get_db
from ..core.security import decode_access_token
from ..models import DevicePushToken, User
from ..schemas.call import (
    DevicePushTokenRequest,
    TurnCredentialsResponse,
)
from ..services.signaling_manager import secure_call_manager

router = APIRouter(tags=["Call Signaling"])

def get_current_user_id_from_token(token: str) -> int:
    """Helper to validate JWT token and extract user_id."""
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")
    try:
        return int(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Malformed user subject in token")


# ── 1. Authenticated WebSocket Signaling Endpoint ─────────────────────────────
@router.websocket("/ws/call")
async def secure_call_websocket(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
):
    """
    Primary authenticated WebSocket signaling endpoint for WebRTC voice and video calls.
    Requires a valid JWT access token passed via query parameter (?token=<JWT>).
    """
    if not token:
        await websocket.close(code=4001, reason="Authentication token required")
        return

    user_id = await secure_call_manager.authenticate_socket(token)
    if user_id is None:
        await websocket.close(code=4001, reason="Invalid or expired authentication token")
        return

    await secure_call_manager.connect(user_id, websocket)
    try:
        # Acknowledge successful authenticated connection
        await websocket.send_json({
            "type": "authenticated",
            "user_id": user_id,
            "status": "ready"
        })

        while True:
            data = await websocket.receive_json()
            await secure_call_manager.handle_signaling_event(user_id, data, websocket)
    except WebSocketDisconnect:
        await secure_call_manager.disconnect(user_id, websocket)
    except Exception as e:
        print(f"[WS ERROR for user {user_id}]: {e}")
        await secure_call_manager.disconnect(user_id, websocket)


# ── 2. Backward-Compatible Legacy WebSocket Path ──────────────────────────────
@router.websocket("/ws/call/{user_id}")
async def legacy_call_websocket(
    websocket: WebSocket,
    user_id: int,
    token: Optional[str] = Query(None),
):
    """
    Backward-compatible path that enforces JWT authentication and identity matching.
    """
    if not token:
        await websocket.close(code=4001, reason="Authentication token required")
        return

    auth_user_id = await secure_call_manager.authenticate_socket(token)
    if auth_user_id is None or auth_user_id != user_id:
        await websocket.close(code=4003, reason="Forbidden: Token does not match requested user ID")
        return

    await secure_call_manager.connect(user_id, websocket)
    try:
        await websocket.send_json({
            "type": "authenticated",
            "user_id": user_id,
            "status": "ready"
        })
        while True:
            data = await websocket.receive_json()
            await secure_call_manager.handle_signaling_event(user_id, data, websocket)
    except WebSocketDisconnect:
        await secure_call_manager.disconnect(user_id, websocket)
    except Exception:
        await secure_call_manager.disconnect(user_id, websocket)


# ── 3. Device Push Token Registration (For Background Wakeups) ────────────────
@router.post("/call/device-token")
def register_device_push_token(
    request: DevicePushTokenRequest,
    db: Session = Depends(get_db),
    token: str = Query(..., description="Access token"),
):
    """
    Registers an FCM / APNs device push token for the authenticated user
    to support incoming call alerts when app is backgrounded or screen is locked.
    """
    user_id = get_current_user_id_from_token(token)

    existing = db.query(DevicePushToken).filter(DevicePushToken.token == request.token).first()
    if existing:
        existing.user_id = user_id
        existing.platform = request.platform
    else:
        new_token = DevicePushToken(
            user_id=user_id,
            token=request.token,
            platform=request.platform,
        )
        db.add(new_token)

    db.commit()
    return {"status": "registered", "user_id": user_id, "platform": request.platform}


@router.delete("/call/device-token")
def unregister_device_push_token(
    token_str: str = Query(..., alias="token"),
    db: Session = Depends(get_db),
    auth_token: str = Query(..., alias="auth_token"),
):
    """Removes a push token when user logs out."""
    user_id = get_current_user_id_from_token(auth_token)
    deleted_count = (
        db.query(DevicePushToken)
        .filter(
            (DevicePushToken.user_id == user_id) &
            (DevicePushToken.token == token_str)
        )
        .delete()
    )
    db.commit()
    return {"status": "unregistered", "deleted": deleted_count > 0}


# ── 4. STUN & Ephemeral TURN Credentials Endpoint ─────────────────────────────
@router.get("/call/turn-credentials", response_model=TurnCredentialsResponse)
def get_turn_credentials(
    token: str = Query(..., description="Access token"),
):
    """
    Generates time-limited ephemeral TURN credentials using HMAC-SHA1
    (coturn REST API standard) and provides STUN servers for ICE discovery.
    """
    user_id = get_current_user_id_from_token(token)

    turn_secret = os.getenv("TURN_SECRET")
    turn_host = os.getenv("TURN_HOST")
    turn_port = os.getenv("TURN_PORT", "3478")
    turn_tls_port = os.getenv("TURN_TLS_PORT", "5349")
    turn_username = os.getenv("TURN_USERNAME")
    turn_password = os.getenv("TURN_PASSWORD")
    turn_urls = os.getenv("TURN_URLS")

    # Time-to-live: 2 hours (7200 seconds)
    ttl = 7200
    expiry_timestamp = int(time.time()) + ttl
    username = f"{expiry_timestamp}:{user_id}"

    if turn_urls and turn_username and turn_password:
        uris = [u.strip() for u in turn_urls.split(",") if u.strip()]
        return TurnCredentialsResponse(
            username=turn_username,
            password=turn_password,
            ttl=ttl,
            uris=uris,
        )

    if turn_secret and turn_host and turn_host != "turn.twoofus.app":
        hashed = hmac.new(turn_secret.encode('utf-8'), username.encode('utf-8'), hashlib.sha1)
        password = base64.b64encode(hashed.digest()).decode('utf-8')
        uris = [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302",
            "stun:stun2.l.google.com:19302",
            "stun:stun.cloudflare.com:3478",
            f"turn:{turn_host}:{turn_port}?transport=udp",
            f"turn:{turn_host}:{turn_port}?transport=tcp",
            f"turns:{turn_host}:{turn_tls_port}?transport=tcp",
        ]
        return TurnCredentialsResponse(
            username=username,
            password=password,
            ttl=ttl,
            uris=uris,
        )
    else:
        # High-availability production OpenRelay TURN & global STUN
        username = "openrelayproject"
        password = "openrelayproject"
        uris = [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302",
            "stun:stun2.l.google.com:19302",
            "stun:stun3.l.google.com:19302",
            "stun:stun4.l.google.com:19302",
            "stun:stun.cloudflare.com:3478",
            "turn:openrelay.metered.ca:80",
            "turn:openrelay.metered.ca:443",
            "turn:openrelay.metered.ca:443?transport=tcp",
        ]

    return TurnCredentialsResponse(
        username=username,
        password=password,
        ttl=ttl,
        uris=uris,
    )
