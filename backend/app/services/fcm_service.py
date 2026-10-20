import json
import logging
import os
from typing import Any, Callable, Dict, List, Optional
from sqlalchemy.orm import Session
from ..models import DevicePushToken

logger = logging.getLogger(__name__)

_firebase_initialized = False
_missing_credentials_logged = False
_mock_fcm_sender: Optional[Callable] = None  # Hook for tests


def set_mock_fcm_sender(sender_fn: Optional[Callable]):
    """Allows test suites to mock FCM sending and simulate delivery or invalid tokens."""
    global _mock_fcm_sender
    _mock_fcm_sender = sender_fn


def _get_firebase_app() -> bool:
    """
    Initializes Firebase Admin SDK using the FIREBASE_CREDENTIALS_JSON environment variable.
    If the environment variable is missing or empty, logs once and returns False (never crashes).
    """
    global _firebase_initialized, _missing_credentials_logged
    if _firebase_initialized:
        return True

    creds_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
    if not creds_json or not creds_json.strip():
        if not _missing_credentials_logged:
            print("[FCM] FIREBASE_CREDENTIALS_JSON not configured, skipping push notification", flush=True)
            _missing_credentials_logged = True
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred_dict = json.loads(creds_json)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
        _firebase_initialized = True
        print("[FCM] Initialized Firebase Admin SDK from FIREBASE_CREDENTIALS_JSON", flush=True)
        return True
    except ImportError:
        if not _missing_credentials_logged:
            print("[FCM] firebase-admin package is not installed; push notifications disabled", flush=True)
            _missing_credentials_logged = True
        return False
    except Exception as e:
        print(f"[FCM] Failed to initialize Firebase Admin SDK: {e}", flush=True)
        return False


def send_call_push_notification(
    db: Session,
    user_id: int,
    call_id: int,
    caller_name: str,
    call_type: str,
) -> int:
    """
    Sends a high-priority DATA message (call_id, caller name, call_type) to all
    registered DevicePushToken rows of the given user_id.
    Deletes tokens reported as invalid or unregistered by FCM.
    Returns the count of successfully dispatched push notifications.
    """
    tokens: List[DevicePushToken] = (
        db.query(DevicePushToken)
        .filter(DevicePushToken.user_id == user_id)
        .all()
    )
    if not tokens:
        return 0

    # If test mock sender is configured, delegate directly
    if _mock_fcm_sender is not None:
        return _mock_fcm_sender(db, user_id, tokens, call_id, caller_name, call_type)

    if not _get_firebase_app():
        return 0

    try:
        from firebase_admin import messaging
        from firebase_admin.exceptions import FirebaseError
    except ImportError:
        print("[FCM] firebase-admin package not found. Skipping push notification.", flush=True)
        return 0

    dispatched = 0
    tokens_to_delete = []

    for t in tokens:
        token_str = getattr(t, "token", "")
        if not token_str:
            tokens_to_delete.append(t)
            continue

        try:
            message = messaging.Message(
                data={
                    "type": "incoming_call",
                    "call_id": str(call_id),
                    "caller_name": str(caller_name),
                    "call_type": str(call_type),
                },
                android=messaging.AndroidConfig(
                    priority="high",
                ),
                token=token_str,
            )
            messaging.send(message)
            dispatched += 1
            print(f"[FCM] Sent high-priority incoming call push to user {user_id} (token {t.id})", flush=True)
        except (messaging.UnregisteredError, messaging.SenderIdMismatchError) as ue:
            print(f"[FCM] Token {t.id} unregistered/invalid ({ue}). Deleting from database.", flush=True)
            tokens_to_delete.append(t)
        except FirebaseError as fe:
            code = getattr(fe, "code", "")
            if code in ("NOT_FOUND", "UNREGISTERED", "INVALID_ARGUMENT"):
                print(f"[FCM] Token {t.id} rejected with code {code}. Deleting from database.", flush=True)
                tokens_to_delete.append(t)
            else:
                print(f"[FCM] Firebase error sending to token {t.id}: {fe}", flush=True)
        except Exception as ex:
            print(f"[FCM] Unexpected exception sending to token {t.id}: {ex}", flush=True)

    if tokens_to_delete:
        for t in tokens_to_delete:
            db.delete(t)
        db.commit()
        print(f"[FCM] Cleaned up {len(tokens_to_delete)} invalid push tokens for user {user_id}", flush=True)

    return dispatched
