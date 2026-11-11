import base64
import hashlib
import hmac
import os
import time
import traceback
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
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
bearer_security = HTTPBearer(auto_error=False)

def get_current_user_id_from_token(token: str) -> int:
    """Helper to validate JWT token and extract user_id."""
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")
    if payload.get("type") == "2fa_pending":
        raise HTTPException(status_code=401, detail="Two-factor authentication required")
    try:
        return int(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Malformed user subject in token")


def get_current_user_from_req(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_security),
    token: Optional[str] = Query(None, description="Access token fallback"),
    auth_token: Optional[str] = Query(None, description="Auth token fallback"),
) -> int:
    """
    Extracts authenticated user_id preferring Authorization: Bearer header
    over URL query parameters to avoid leaking tokens in logs.
    """
    raw_token = None
    if credentials and credentials.credentials:
        raw_token = credentials.credentials
    elif token:
        raw_token = token
    elif auth_token:
        raw_token = auth_token

    if not raw_token:
        raise HTTPException(status_code=401, detail="Authentication token required")

    return get_current_user_id_from_token(raw_token)


# ── 1. Authenticated WebSocket Signaling Endpoint ─────────────────────────────
@router.websocket("/ws/call")
async def secure_call_websocket(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
    ticket: Optional[str] = Query(None),
):
    """
    Primary authenticated WebSocket signaling endpoint for WebRTC voice and video calls.
    Supports either:
    1. Single-use ticket (?ticket=<ticket>) issued via POST /call/ticket (Recommended, Phase 3 hardened).
    2. JWT access token (?token=<JWT>) (Backward-compatible).
    """
    user_id: Optional[int] = None
    if ticket:
        user_id = secure_call_manager.redeem_ticket(ticket)
        if user_id is None:
            await websocket.close(code=4001, reason="Invalid or expired ticket")
            return
    elif token:
        user_id = await secure_call_manager.authenticate_socket(token)
        if user_id is None:
            await websocket.close(code=4001, reason="Invalid or expired authentication token")
            return
    else:
        await websocket.close(code=4001, reason="Authentication token or ticket required")
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
    except WebSocketDisconnect as ws_disc:
        code = getattr(ws_disc, "code", "unknown")
        reason = getattr(ws_disc, "reason", "")
        print(f"[WS DISCONNECT for user {user_id}]: code={code}, reason='{reason}'", flush=True)
        await secure_call_manager.disconnect(user_id, websocket)
    except Exception as e:
        print(f"[WS UNEXPECTED ERROR for user {user_id}]: {e}\n{traceback.format_exc()}", flush=True)
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
    except WebSocketDisconnect as ws_disc:
        code = getattr(ws_disc, "code", "unknown")
        reason = getattr(ws_disc, "reason", "")
        print(f"[Legacy WS DISCONNECT for user {user_id}]: code={code}, reason='{reason}'", flush=True)
        await secure_call_manager.disconnect(user_id, websocket)
    except Exception as e:
        print(f"[Legacy WS UNEXPECTED ERROR for user {user_id}]: {e}\n{traceback.format_exc()}", flush=True)
        await secure_call_manager.disconnect(user_id, websocket)


# ── 2.1 Single-Use WS Ticket Issuer (Phase 3 Hardened Auth) ───────────────────
@router.post("/call/ticket")
def create_call_ticket(
    user_id: int = Depends(get_current_user_from_req),
):
    """Issues a short-lived (60s) single-use WebSocket authentication ticket."""
    ticket = secure_call_manager.create_ticket(user_id)
    return {"ticket": ticket, "expires_in": 60}


# ── 2.2 Diagnostic Call Debug Endpoint ────────────────────────────────────────
@router.get("/call/debug")
def get_call_debug(
    user_id: int = Depends(get_current_user_from_req),
):
    """Diagnostic endpoint returning ICE configuration and WebSocket connection status."""
    turn_creds = get_turn_credentials(user_id=user_id)
    return {
        "user_id": user_id,
        "call_debug_enabled": os.getenv("CALL_DEBUG", "true").lower() == "true",
        "turn_configured": bool(os.getenv("TURN_SECRET") or os.getenv("TURN_USERNAME") or os.getenv("TURN_URLS")),
        "turn_host": os.getenv("TURN_HOST", "openrelay.metered.ca (default)"),
        "ice_servers": turn_creds.uris,
        "active_ws_connections_count": secure_call_manager.get_user_socket_count(user_id),
        "is_user_online": secure_call_manager.is_user_online(user_id),
    }


# ── 3. Device Push Token Registration (For Background Wakeups) ────────────────
@router.post("/call/device-token")
def register_device_push_token(
    request: DevicePushTokenRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_from_req),
):
    """
    Registers an FCM / APNs device push token for the authenticated user
    to support incoming call alerts when app is backgrounded or screen is locked.
    """
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
    user_id: int = Depends(get_current_user_from_req),
):
    """Removes a push token when user logs out."""
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
    user_id: int = Depends(get_current_user_from_req),
):
    """
    Generates time-limited ephemeral TURN credentials using HMAC-SHA1
    (coturn REST API standard) and provides STUN servers for ICE discovery.
    """

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
