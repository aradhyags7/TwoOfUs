import os
import time
import threading
from collections import defaultdict, deque
from typing import Callable, Optional
from fastapi import HTTPException, Request

RATE_LIMIT_ENABLED = os.getenv("RATE_LIMIT_ENABLED", "true").lower() in ("true", "1", "yes")


class SlidingWindowRateLimiter:
    """Thread-safe in-memory sliding window rate limiter."""

    def __init__(self, max_requests: int, window_seconds: int, prefix: str = ""):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.prefix = prefix
        self._history = defaultdict(deque)
        self._lock = threading.Lock()

    def _get_client_identifier(self, request: Request) -> str:
        # Extract IP address prioritizing forwarded headers from reverse proxies (Render, Cloudflare)
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            ip = forwarded.split(",")[0].strip()
        elif request.client and request.client.host:
            ip = request.client.host
        else:
            ip = "unknown"
        return f"{self.prefix}:{ip}"

    def check(self, request: Request) -> None:
        if not RATE_LIMIT_ENABLED:
            return

        key = self._get_client_identifier(request)
        now = time.time()
        window_start = now - self.window_seconds

        with self._lock:
            queue = self._history[key]
            # Purge timestamps outside the active sliding window
            while queue and queue[0] < window_start:
                queue.popleft()

            if len(queue) >= self.max_requests:
                oldest = queue[0]
                retry_after = max(1, int(oldest + self.window_seconds - now))
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many requests. Please wait {retry_after} seconds before trying again.",
                    headers={"Retry-After": str(retry_after)},
                )

            queue.append(now)

    def reset(self) -> None:
        """Clear recorded timestamps (useful for tests)."""
        with self._lock:
            self._history.clear()


def create_rate_limiter(max_requests: int, window_seconds: int, prefix: str = "") -> Callable[[Request], None]:
    """Factory creating a FastAPI dependency that enforces a rate limit."""
    limiter = SlidingWindowRateLimiter(max_requests=max_requests, window_seconds=window_seconds, prefix=prefix)

    def dependency(request: Request) -> None:
        limiter.check(request)

    # Attach limiter instance for direct introspection/reset in tests
    dependency.limiter = limiter  # type: ignore[attr-defined]
    return dependency


# Global rate limiter dependencies for sensitive routes
rate_limit_login = create_rate_limiter(max_requests=60, window_seconds=60, prefix="login")
rate_limit_otp = create_rate_limiter(max_requests=60, window_seconds=60, prefix="otp")
rate_limit_pin = create_rate_limiter(max_requests=60, window_seconds=60, prefix="pin")
rate_limit_reset = create_rate_limiter(max_requests=30, window_seconds=60, prefix="reset")
