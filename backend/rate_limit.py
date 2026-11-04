"""تحديد معدّل الطلبات البسيط في الذاكرة لكل عنوان IP.

مناسب للتطوير ونشر نسخة واحدة. للإنتاج مع عدة نسخ استخدم Redis أو بوابة (Cloudflare).
"""
import os
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Tuple

from fastapi import HTTPException, Request
from starlette.middleware.base import BaseHTTPMiddleware

AUTH_LIMIT = int(os.getenv("RATE_LIMIT_AUTH", "20"))
AUTH_WINDOW = int(os.getenv("RATE_LIMIT_AUTH_WINDOW", "60"))
GENERAL_LIMIT = int(os.getenv("RATE_LIMIT_GENERAL", "120"))
GENERAL_WINDOW = int(os.getenv("RATE_LIMIT_GENERAL_WINDOW", "60"))

_AUTH_PATHS = {"/auth/register", "/auth/login", "/auth/forgot-password", "/auth/reset-password", "/auth/oauth"}


class _Bucket:
    def __init__(self) -> None:
        self.hits: Deque[float] = deque()
        self.lock = threading.Lock()


_buckets: Dict[Tuple[str, str], _Bucket] = defaultdict(_Bucket)
_cleanup_lock = threading.Lock()
_last_cleanup = 0.0


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


def _check(key: Tuple[str, str], limit: int, window: int) -> None:
    now = time.time()
    bucket = _buckets[key]
    with bucket.lock:
        while bucket.hits and bucket.hits[0] <= now - window:
            bucket.hits.popleft()
        if len(bucket.hits) >= limit:
            raise HTTPException(
                status_code=429,
                detail="تجاوزت حد الطلبات، انتظر قليلاً ثم حاول مرة أخرى.",
            )
        bucket.hits.append(now)

    global _last_cleanup
    if now - _last_cleanup > 300:
        with _cleanup_lock:
            if now - _last_cleanup > 300:
                _last_cleanup = now
                stale = [k for k, b in list(_buckets.items()) if not b.hits or b.hits[-1] < now - 600]
                for k in stale:
                    _buckets.pop(k, None)


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS":
            return await call_next(request)
        path = request.url.path.rstrip("/") or "/"
        ip = _client_ip(request)
        if path in _AUTH_PATHS or path.startswith("/auth/"):
            _check((ip, "auth"), AUTH_LIMIT, AUTH_WINDOW)
        else:
            _check((ip, "gen"), GENERAL_LIMIT, GENERAL_WINDOW)
        return await call_next(request)
