import asyncio
from datetime import datetime, timezone
import json
import time
from typing import Any, Dict, List, Optional, Set
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from ..core.security import decode_access_token
from ..core.database import SessionLocal
from ..models import CallSession, Pair, User, Message

def _to_utc_iso(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def _get_db_session() -> Session:
    try:
        from ..main import app, get_db as main_get_db
        if main_get_db in app.dependency_overrides:
            return next(app.dependency_overrides[main_get_db]())
        from ..core.database import get_db as core_get_db
        if core_get_db in app.dependency_overrides:
            return next(app.dependency_overrides[core_get_db]())
    except Exception as e:
        pass
    return SessionLocal()




class SecureSignalingManager:
    def __init__(self):
        # Maps user_id -> Set of active WebSocket connections
        self._connections: Dict[int, Set[WebSocket]] = {}
        # Rate-limiting tracking: user_id -> list of signal timestamps in current window
        self._rate_limits: Dict[int, List[float]] = {}
        # Max signaling messages allowed per 1-second window
        self._rate_limit_max_per_sec = 40
        # Lock for connection registry modifications
        self._lock = asyncio.Lock()

    async def authenticate_socket(self, token: str) -> Optional[int]:
        """Validates JWT token and extracts user_id. Returns None if invalid or expired."""
        if not token:
            return None
        payload = decode_access_token(token)
        if not payload or "sub" not in payload:
            return None
        try:
            return int(payload["sub"])
        except (ValueError, TypeError):
            return None

    async def connect(self, user_id: int, websocket: WebSocket):
        """Registers an authenticated WebSocket connection."""
        await websocket.accept()
        async with self._lock:
            if user_id not in self._connections:
                self._connections[user_id] = set()
            self._connections[user_id].add(websocket)

    async def disconnect(self, user_id: int, websocket: WebSocket):
        """Removes a WebSocket connection and cleans up empty sets."""
        async with self._lock:
            if user_id in self._connections:
                self._connections[user_id].discard(websocket)
                if not self._connections[user_id]:
                    del self._connections[user_id]
            if user_id in self._rate_limits:
                del self._rate_limits[user_id]

    def is_user_online(self, user_id: int) -> bool:
        """Checks if user has at least one active signaling WebSocket."""
        return user_id in self._connections and len(self._connections[user_id]) > 0

    def _check_rate_limit(self, user_id: int) -> bool:
        """Applies a sliding 1-second window rate limit. Returns True if permitted."""
        now = time.time()
        timestamps = self._rate_limits.setdefault(user_id, [])
        # Prune older than 1 second
        self._rate_limits[user_id] = [t for t in timestamps if now - t < 1.0]
        if len(self._rate_limits[user_id]) >= self._rate_limit_max_per_sec:
            return False
        self._rate_limits[user_id].append(now)
        return True

    async def send_to_user(self, user_id: int, message: Dict[str, Any]) -> bool:
        """Sends a JSON message to all active sockets of a user."""
        sockets = set()
        async with self._lock:
            if user_id in self._connections:
                sockets = set(self._connections[user_id])

        if not sockets:
            return False

        dead_sockets = []
        delivered = False
        for ws in sockets:
            try:
                await ws.send_json(message)
                delivered = True
            except Exception:
                dead_sockets.append(ws)

        if dead_sockets:
            async with self._lock:
                if user_id in self._connections:
                    for ws in dead_sockets:
                        self._connections[user_id].discard(ws)
                    if not self._connections[user_id]:
                        del self._connections[user_id]

        return delivered

    def _verify_pairing(self, db: Session, user1_id: int, user2_id: int) -> bool:
        """Ensures both users belong to an active confirmed Pair."""
        pair = (
            db.query(Pair)
            .filter(
                ((Pair.user1_id == user1_id) & (Pair.user2_id == user2_id)) |
                ((Pair.user1_id == user2_id) & (Pair.user2_id == user1_id))
            )
            .first()
        )
        return pair is not None

    def _create_call_log_message(self, db: Session, session: CallSession):
        """Creates a CALL_LOG message in chat history so both partners see the record."""
        try:
            caller_id = int(getattr(session, "caller_id"))
            receiver_id = int(getattr(session, "receiver_id"))
            call_id = int(getattr(session, "id"))
            call_type = str(getattr(session, "call_type", "voice"))
            status = str(getattr(session, "status", "ended"))
            duration_seconds = int(getattr(session, "duration_seconds", 0))

            call_payload = {
                "call_id": call_id,
                "caller_id": caller_id,
                "receiver_id": receiver_id,
                "call_type": call_type,
                "status": status,
                "duration_seconds": duration_seconds,
                "ended_at": _to_utc_iso(session.ended_at) if session.ended_at else _to_utc_iso(datetime.now(timezone.utc)),
            }
            content_str = f"CALL_LOG:{json.dumps(call_payload)}"
            msg = Message(
                sender_id=caller_id,
                receiver_id=receiver_id,
                content=content_str,
                is_encrypted=False,
                created_at=datetime.now(timezone.utc),
            )
            db.add(msg)
            db.commit()
        except Exception as e:
            print(f"[CALL_LOG ERROR]: {e}")

    async def handle_signaling_event(
        self,
        sender_id: int,
        raw_data: Any,
        websocket: WebSocket
    ):
        """
        Validates, authorizes, and dispatches real-time signaling events.
        Enforces strict authentication, relationship authorization, and call state bounds.
        """
        if not isinstance(raw_data, dict):
            await websocket.send_json({"type": "error", "detail": "Malformed JSON payload"})
            return

        if not self._check_rate_limit(sender_id):
            await websocket.send_json({"type": "error", "code": 429, "detail": "Signaling rate limit exceeded"})
            return

        msg_type = raw_data.get("type")
        if not msg_type:
            await websocket.send_json({"type": "error", "detail": "Missing message type"})
            return

        # ── 1. Heartbeat ─────────────────────────────────────────────────────
        if msg_type == "ping":
            await websocket.send_json({"type": "pong", "timestamp": _to_utc_iso(datetime.now(timezone.utc))})
            return

        target_id = raw_data.get("target_id") or raw_data.get("target_user_id")
        call_id = raw_data.get("call_id")
        payload = raw_data.get("payload", {})
        now = datetime.now(timezone.utc)

        db: Session = _get_db_session()
        try:
            # ── 2. Relationship Verification ─────────────────────────────────
            if target_id is not None:
                try:
                    target_id = int(target_id)
                except (ValueError, TypeError):
                    await websocket.send_json({"type": "error", "detail": "Invalid target_id"})
                    return

                if not self._verify_pairing(db, sender_id, target_id):
                    await websocket.send_json({
                        "type": "error",
                        "code": 403,
                        "detail": "Target user is not your paired partner"
                    })
                    return

            # ── 3. Call Invitation (Initiate Call) ────────────────────────────
            if msg_type == "call_invite":
                if target_id is None:
                    await websocket.send_json({"type": "error", "detail": "Missing target_id for call_invite"})
                    return

                call_type = raw_data.get("call_type") or payload.get("call_type", "voice")
                if call_type not in ("voice", "video"):
                    call_type = "voice"

                # Check if target is already in an ongoing call
                active_call = (
                    db.query(CallSession)
                    .filter(
                        (CallSession.status.in_(["ringing", "ongoing"])) &
                        ((CallSession.caller_id == target_id) | (CallSession.receiver_id == target_id))
                    )
                    .first()
                )
                if active_call:
                    await websocket.send_json({
                        "type": "call_busy",
                        "target_id": target_id,
                        "detail": "Partner is currently in another call",
                    })
                    return

                # Cancel any hanging ringing calls between this pair
                prev_hanging = (
                    db.query(CallSession)
                    .filter(
                        (CallSession.status == "ringing") &
                        (((CallSession.caller_id == sender_id) & (CallSession.receiver_id == target_id)) |
                         ((CallSession.caller_id == target_id) & (CallSession.receiver_id == sender_id)))
                    )
                    .all()
                )
                for c in prev_hanging:
                    c.status = "missed"
                    c.ended_at = now
                    c.ended_reason = "superseded_by_new_call"

                new_session = CallSession(
                    caller_id=sender_id,
                    receiver_id=target_id,
                    call_type=call_type,
                    status="ringing",
                    created_at=now,
                )
                db.add(new_session)
                db.commit()
                db.refresh(new_session)

                sender_user = db.query(User).filter(User.id == sender_id).first()
                caller_name = sender_user.username if sender_user else "Partner"

                # Confirm to caller with session details
                await websocket.send_json({
                    "type": "call_initiated",
                    "call_id": new_session.id,
                    "target_id": target_id,
                    "call_type": call_type,
                    "status": "ringing",
                    "created_at": _to_utc_iso(new_session.created_at),
                })

                # Alert receiver over WebSocket if online
                delivered = await self.send_to_user(
                    target_id,
                    {
                        "type": "incoming_call",
                        "call_id": new_session.id,
                        "caller_id": sender_id,
                        "caller_name": caller_name,
                        "call_type": call_type,
                        "created_at": _to_utc_iso(new_session.created_at),
                    }
                )

                if delivered:
                    # Notify caller that receiver's device is ringing
                    await websocket.send_json({
                        "type": "call_ringing",
                        "call_id": new_session.id,
                        "target_id": target_id,
                    })

                return

            # ── 4. Call State Guard for Active Signals ────────────────────────
            if call_id is None:
                await websocket.send_json({"type": "error", "detail": "Missing call_id"})
                return

            session = db.query(CallSession).filter(CallSession.id == call_id).first()
            if not session:
                await websocket.send_json({"type": "error", "detail": "Call session not found"})
                return

            caller_id = int(getattr(session, "caller_id"))
            receiver_id = int(getattr(session, "receiver_id"))
            if sender_id not in (caller_id, receiver_id):
                await websocket.send_json({"type": "error", "code": 403, "detail": "Not a participant in this call"})
                return

            other_party_id = receiver_id if sender_id == caller_id else caller_id

            # ── 5. Call Acceptance ───────────────────────────────────────────
            if msg_type in ("call_accept", "call_accepted"):
                if str(getattr(session, "status")) != "ongoing":
                    session.status = "ongoing"
                    session.started_at = now
                    db.commit()
                    db.refresh(session)

                await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_accepted",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "started_at": _to_utc_iso(session.started_at),
                    }
                )
                return

            # ── 6. Call Rejection ────────────────────────────────────────────
            if msg_type in ("call_reject", "call_rejected"):
                session.status = "rejected"
                session.ended_at = now
                session.rejection_reason = raw_data.get("reason") or "declined"
                db.commit()
                db.refresh(session)

                self._create_call_log_message(db, session)

                await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_rejected",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "reason": session.rejection_reason,
                    }
                )
                return

            # ── 7. Call Cancellation (Caller cancels before answer) ──────────
            if msg_type in ("call_cancel", "call_cancelled"):
                session.status = "missed"
                session.ended_at = now
                session.ended_reason = "caller_cancelled"
                db.commit()
                db.refresh(session)

                self._create_call_log_message(db, session)

                await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_cancelled",
                        "call_id": session.id,
                        "sender_id": sender_id,
                    }
                )
                return

            # ── 8. Call Termination (Hang up) ────────────────────────────────
            if msg_type in ("call_end", "call_ended"):
                current_status = str(getattr(session, "status", ""))
                if current_status != "ended":
                    if current_status == "ringing":
                        session.status = "missed" if sender_id == caller_id else "rejected"
                    else:
                        session.status = "ended"

                    session.ended_at = now
                    session.ended_reason = raw_data.get("reason") or "normal_hangup"

                    if session.started_at:
                        started = session.started_at
                        if started.tzinfo is None:
                            started = started.replace(tzinfo=timezone.utc)
                        duration = int((now - started).total_seconds())
                        session.duration_seconds = max(0, duration)

                    db.commit()
                    db.refresh(session)

                    self._create_call_log_message(db, session)

                await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_ended",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "duration_seconds": session.duration_seconds,
                        "status": session.status,
                    }
                )
                return

            # ── 9. WebRTC Media Signaling (Offer, Answer, ICE Candidates) ────
            if msg_type in ("webrtc_offer", "webrtc_answer", "webrtc_ice_candidate", "offer", "answer", "ice_candidate"):
                current_status = str(getattr(session, "status", ""))
                # Only allow forwarding SDP/ICE when call is in valid state
                if current_status not in ("ringing", "ongoing", "connecting"):
                    await websocket.send_json({
                        "type": "error",
                        "detail": f"Cannot forward media signal: call is in '{current_status}' state"
                    })
                    return

                # Forward signal securely to partner
                await self.send_to_user(
                    other_party_id,
                    {
                        "version": "1.0",
                        "type": msg_type,
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "target_id": other_party_id,
                        "timestamp": _to_utc_iso(now),
                        "payload": payload,
                    }
                )
                return

            # Unhandled message type
            await websocket.send_json({
                "type": "error",
                "detail": f"Unknown signaling event type: '{msg_type}'"
            })

        finally:
            db.close()


# Global secure signaling manager singleton
secure_call_manager = SecureSignalingManager()
