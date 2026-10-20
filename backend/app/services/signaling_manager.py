import asyncio
from datetime import datetime, timezone, timedelta
import json
import os
import time
from typing import Any, Dict, List, Optional, Set, Tuple
import uuid
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from ..core.security import decode_access_token
from ..core.database import SessionLocal
from ..models import CallSession, Pair, User, Message

def _to_utc_iso(dt: Any) -> Optional[str]:
    if dt is None:
        return None
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.isoformat()
    return str(dt)


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
        # Single-use short-lived WS tickets: ticket_str -> (user_id, expires_at)
        self._tickets: Dict[str, Tuple[int, float]] = {}
        # Pending ringing ack events for online callees: call_id -> asyncio.Event
        self._pending_ringing_acks: Dict[int, asyncio.Event] = {}
        # Timeout in seconds to wait for callee call_ringing ack before fallback to FCM push
        self._ringing_ack_timeout: float = 3.0
        # Lock for connection registry modifications
        self._lock = asyncio.Lock()
        # Diagnostic debug logging flag
        self._call_debug = os.getenv("CALL_DEBUG", "true").lower() == "true"

    def _log(self, msg: str):
        """Diagnostic logger enabled via CALL_DEBUG environment variable."""
        if self._call_debug:
            print(f"[CALL_DEBUG] {msg}", flush=True)

    async def _wait_for_ringing_ack_or_push(
        self,
        session_id: int,
        target_id: int,
        caller_name: str,
        call_type: str,
        ack_event: asyncio.Event,
    ):
        """
        Waits up to _ringing_ack_timeout (default 3.0s) for callee to acknowledge ringing.
        If no call_ringing ack arrives within 3 seconds, dispatches fallback high-priority FCM data push.
        """
        timeout_seconds = self._ringing_ack_timeout
        try:
            try:
                await asyncio.wait_for(ack_event.wait(), timeout=timeout_seconds)
                self._log(f"call_ringing ack confirmed within {timeout_seconds}s for call_id={session_id}")
                return
            except asyncio.TimeoutError:
                self._log(f"No call_ringing ack within {timeout_seconds}s for call_id={session_id}, attempting fallback FCM push")

            db = _get_db_session()
            try:
                session = db.query(CallSession).filter(CallSession.id == session_id).first()
                if not session or str(getattr(session, "status", "")) != "ringing":
                    self._log(f"Call {session_id} is no longer in ringing state, skipping fallback FCM push")
                    return

                from .fcm_service import send_call_push_notification
                push_sent = send_call_push_notification(
                    db,
                    user_id=target_id,
                    call_id=session_id,
                    caller_name=caller_name,
                    call_type=call_type,
                )
                self._log(f"Fallback FCM push dispatched to {push_sent} device(s) for call_id={session_id}")
            finally:
                db.close()
        except Exception as e:
            self._log(f"Exception in _wait_for_ringing_ack_or_push for call_id={session_id}: {e}")
        finally:
            self._pending_ringing_acks.pop(session_id, None)

    def create_ticket(self, user_id: int) -> str:
        """Generates a short-lived (60s) single-use WebSocket ticket."""
        now = time.time()
        ticket = f"call_ticket_{uuid.uuid4().hex}"
        # Prune expired tickets
        self._tickets = {k: v for k, v in self._tickets.items() if v[1] > now}
        self._tickets[ticket] = (user_id, now + 60.0)
        self._log(f"Created single-use WS ticket for user {user_id}")
        return ticket

    def redeem_ticket(self, ticket: str) -> Optional[int]:
        """Validates and redeems a single-use WebSocket ticket."""
        now = time.time()
        if not ticket or ticket not in self._tickets:
            self._log(f"Rejected invalid or non-existent ticket: {ticket}")
            return None
        user_id, expires_at = self._tickets.pop(ticket)
        if now > expires_at:
            self._log(f"Rejected expired ticket for user {user_id}")
            return None
        self._log(f"Successfully redeemed single-use ticket for user {user_id}")
        return user_id

    def get_user_socket_count(self, user_id: int) -> int:
        """Returns count of active WebSocket connections for user."""
        return len(self._connections.get(user_id, set()))

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
        self._log(f"User {user_id} connected WebSocket (active sockets: {len(self._connections[user_id])})")

    async def disconnect(self, user_id: int, websocket: WebSocket):
        """Removes a WebSocket connection and cleans up empty sets."""
        async with self._lock:
            if user_id in self._connections:
                self._connections[user_id].discard(websocket)
                if not self._connections[user_id]:
                    del self._connections[user_id]
            if user_id in self._rate_limits:
                del self._rate_limits[user_id]
        self._log(f"User {user_id} disconnected WebSocket (remaining sockets: {self.get_user_socket_count(user_id)})")

        # If user has zero active sockets, clean any active sessions where partner is also disconnected
        if not self.is_user_online(user_id):
            db = _get_db_session()
            try:
                self.clean_stale_sessions(db)
            finally:
                db.close()

    def is_user_online(self, user_id: int) -> bool:
        """Checks if user has at least one active signaling WebSocket."""
        return user_id in self._connections and len(self._connections[user_id]) > 0

    def clean_stale_sessions(self, db: Session):
        """
        Cleans up orphan and stale call sessions:
        1. Ringing calls older than 45 seconds are marked as 'missed'.
        2. Ongoing calls where neither participant is online are marked as 'ended'.
        """
        now = datetime.now(timezone.utc)
        stale_ringing_cutoff = now - timedelta(seconds=45)

        # 1. Ringing timeout (45s)
        stale_ringing = (
            db.query(CallSession)
            .filter(
                (CallSession.status == "ringing") &
                (CallSession.created_at < stale_ringing_cutoff)
            )
            .all()
        )
        for c in stale_ringing:
            c.status = "missed"
            c.ended_at = now
            c.ended_reason = "ringing_timeout_45s"
            self._log(f"Cleaned stale ringing session {c.id} -> missed (45s timeout)")

        # 2. Ongoing calls where both participants' WebSockets are gone
        ongoing_calls = (
            db.query(CallSession)
            .filter(CallSession.status == "ongoing")
            .all()
        )
        for c in ongoing_calls:
            c_id = int(getattr(c, "caller_id"))
            r_id = int(getattr(c, "receiver_id"))
            if not self.is_user_online(c_id) and not self.is_user_online(r_id):
                c.status = "ended"
                c.ended_at = now
                c.ended_reason = "both_sockets_disconnected"
                if c.started_at:
                    started = c.started_at.replace(tzinfo=timezone.utc) if c.started_at.tzinfo is None else c.started_at
                    c.duration_seconds = max(0, int((now - started).total_seconds()))
                self._log(f"Cleaned orphan ongoing session {c.id} -> ended (both sockets disconnected)")

        db.commit()

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
        """No-op: Call history resides strictly in call_sessions table to preserve zero plaintext leakage in messages."""
        pass

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

        target_id = raw_data.get("target_id") or raw_data.get("target_user_id") or raw_data.get("receiver_id")
        call_id = raw_data.get("call_id")
        payload = raw_data.get("payload", {})
        now = datetime.now(timezone.utc)

        db: Session = _get_db_session()
        try:
            # ── 1.1 Proactive Stale Sessions Cleanup ─────────────────────────
            self.clean_stale_sessions(db)

            # ── 2. Relationship Verification ─────────────────────────────────
            if target_id is not None:
                try:
                    target_id = int(target_id)
                except (ValueError, TypeError):
                    self._log(f"Rejected invalid target_id from sender={sender_id}: {target_id}")
                    await websocket.send_json({"type": "error", "detail": "Invalid target_id"})
                    return

                if not self._verify_pairing(db, sender_id, target_id):
                    self._log(f"call event {msg_type} REJECTED (unpaired): sender={sender_id}, target={target_id}")
                    await websocket.send_json({
                        "type": "error",
                        "code": 403,
                        "detail": "Target user is not your paired partner"
                    })
                    return

            # ── 3. Call Invitation (Initiate Call) ────────────────────────────
            if msg_type in ("call_invite", "call_request"):
                if target_id is None:
                    self._log(f"{msg_type} REJECTED (missing target_id): sender={sender_id}")
                    await websocket.send_json({"type": "error", "detail": f"Missing target_id for {msg_type}"})
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
                    self._log(f"call_invite REJECTED (target busy): sender={sender_id}, target={target_id}, active_call={active_call.id}, status={active_call.status}")
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

                self._log(
                    f"call_invite: call_id={new_session.id}, sender={sender_id}, target={target_id}, "
                    f"type={call_type}, delivered={delivered}, target_online={self.is_user_online(target_id)}"
                )

                if delivered:
                    # Notify caller that receiver's device is ringing
                    await websocket.send_json({
                        "type": "call_ringing",
                        "call_id": new_session.id,
                        "target_id": target_id,
                    })

                    # Online callee: track ringing ack; fallback to FCM push if no call_ringing arrives within 3s
                    ack_event = asyncio.Event()
                    self._pending_ringing_acks[new_session.id] = ack_event
                    asyncio.create_task(
                        self._wait_for_ringing_ack_or_push(
                            session_id=new_session.id,
                            target_id=target_id,
                            caller_name=caller_name,
                            call_type=call_type,
                            ack_event=ack_event,
                        )
                    )
                else:
                    # Callee has no live WebSocket -> send high-priority FCM data push immediately
                    try:
                        from .fcm_service import send_call_push_notification
                        push_sent = send_call_push_notification(
                            db,
                            user_id=target_id,
                            call_id=new_session.id,
                            caller_name=caller_name,
                            call_type=call_type,
                        )
                        self._log(f"FCM push dispatched to {push_sent} device(s) for offline user {target_id}")
                    except Exception as e:
                        self._log(f"FCM push dispatch exception for user {target_id}: {e}")

                return

            # ── 4. Call State Guard for Active Signals ────────────────────────
            if call_id is None:
                self._log(f"Signaling event '{msg_type}' REJECTED: missing call_id from sender={sender_id}")
                await websocket.send_json({"type": "error", "detail": "Missing call_id"})
                return

            session = db.query(CallSession).filter(CallSession.id == call_id).first()
            if not session:
                self._log(f"Signaling event '{msg_type}' REJECTED: session {call_id} not found")
                await websocket.send_json({"type": "error", "detail": "Call session not found"})
                return

            caller_id = int(getattr(session, "caller_id"))
            receiver_id = int(getattr(session, "receiver_id"))
            if sender_id not in (caller_id, receiver_id):
                self._log(f"Signaling event '{msg_type}' REJECTED (unauthorized participant): sender={sender_id}, call_id={call_id}")
                await websocket.send_json({"type": "error", "code": 403, "detail": "Not a participant in this call"})
                return

            other_party_id = receiver_id if sender_id == caller_id else caller_id

            # ── 4.1 Callee Ringing Ack ───────────────────────────────────────
            if msg_type in ("call_ringing", "ringing"):
                ack_event = self._pending_ringing_acks.pop(session.id, None)
                if ack_event:
                    ack_event.set()
                self._log(f"call_ringing ack received from sender={sender_id} for call_id={session.id}")
                await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_ringing",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "target_id": other_party_id,
                    }
                )
                return

            # Clear pending ringing ack on termination/acceptance
            if msg_type in ("call_accept", "call_accepted", "call_reject", "call_rejected", "call_cancel", "call_cancelled", "call_end", "call_ended"):
                ack_event = self._pending_ringing_acks.pop(session.id, None)
                if ack_event:
                    ack_event.set()

            # ── 5. Callee Ready Notification (WebRTC readiness handshake) ────
            if msg_type in ("callee_ready", "receiver_ready"):
                delivered = await self.send_to_user(
                    other_party_id,
                    {
                        "type": "callee_ready",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "target_id": other_party_id,
                    }
                )
                self._log(f"callee_ready: call_id={session.id}, sender={sender_id}, target={other_party_id}, delivered={delivered}")
                return

            # ── 6. Call Acceptance ───────────────────────────────────────────
            if msg_type in ("call_accept", "call_accepted"):
                if str(getattr(session, "status")) != "ongoing":
                    session.status = "ongoing"
                    session.started_at = now
                    db.commit()
                    db.refresh(session)

                delivered = await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_accepted",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "started_at": _to_utc_iso(session.started_at),
                    }
                )
                self._log(f"call_accept: call_id={session.id}, sender={sender_id}, target={other_party_id}, delivered={delivered}")
                return

            # ── 7. Call Rejection ────────────────────────────────────────────
            if msg_type in ("call_reject", "call_rejected"):
                session.status = "rejected"
                session.ended_at = now
                session.rejection_reason = raw_data.get("reason") or "declined"
                db.commit()
                db.refresh(session)

                self._create_call_log_message(db, session)

                delivered = await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_rejected",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "reason": session.rejection_reason,
                    }
                )
                self._log(f"call_reject: call_id={session.id}, sender={sender_id}, target={other_party_id}, reason={session.rejection_reason}, delivered={delivered}")
                return

            # ── 8. Call Cancellation (Caller cancels before answer) ──────────
            if msg_type in ("call_cancel", "call_cancelled"):
                session.status = "missed"
                session.ended_at = now
                session.ended_reason = "caller_cancelled"
                db.commit()
                db.refresh(session)

                self._create_call_log_message(db, session)

                delivered = await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_cancelled",
                        "call_id": session.id,
                        "sender_id": sender_id,
                    }
                )
                self._log(f"call_cancel: call_id={session.id}, sender={sender_id}, target={other_party_id}, delivered={delivered}")
                return

            # ── 9. Call Termination (Hang up) ────────────────────────────────
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

                delivered = await self.send_to_user(
                    other_party_id,
                    {
                        "type": "call_ended",
                        "call_id": session.id,
                        "sender_id": sender_id,
                        "duration_seconds": session.duration_seconds,
                        "status": session.status,
                    }
                )
                self._log(f"call_end: call_id={session.id}, sender={sender_id}, target={other_party_id}, duration={session.duration_seconds}s, status={session.status}, delivered={delivered}")
                return

            # ── 10. WebRTC Media Signaling (Offer, Answer, ICE Candidates) ───
            if msg_type in ("webrtc_offer", "webrtc_answer", "webrtc_ice_candidate", "offer", "answer", "ice_candidate"):
                current_status = str(getattr(session, "status", ""))
                # Only allow forwarding SDP/ICE when call is in valid state
                if current_status not in ("ringing", "ongoing", "connecting"):
                    self._log(f"Media signal '{msg_type}' REJECTED: call {session.id} is in '{current_status}' state")
                    await websocket.send_json({
                        "type": "error",
                        "detail": f"Cannot forward media signal: call is in '{current_status}' state"
                    })
                    return

                # Forward signal securely to partner
                delivered = await self.send_to_user(
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
                self._log(f"media_signal {msg_type}: call_id={session.id}, sender={sender_id}, target={other_party_id}, delivered={delivered}")
                return

            # Unhandled message type
            self._log(f"Unknown signaling event type '{msg_type}' from sender={sender_id}")
            await websocket.send_json({
                "type": "error",
                "detail": f"Unknown signaling event type: '{msg_type}'"
            })
        finally:
            db.close()


# Global secure signaling manager singleton
secure_call_manager = SecureSignalingManager()
