"""كلمات المرور (scrypt) ورموز الدخول (JWT) واعتماد المستخدم الحالي."""
import hashlib
import hmac
import os
import re
import secrets
import time
from typing import Optional

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import db

TOKEN_DAYS = 30
RESET_TOKEN_HOURS = 2
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_bearer = HTTPBearer(auto_error=False)

PLAN_LIMITS = {
    "free": int(os.getenv("FREE_MONTHLY_LIMIT", "5")),
    "pro": int(os.getenv("PRO_MONTHLY_LIMIT", "300")),
}


def _secret() -> str:
    s = os.getenv("JWT_SECRET")
    if s:
        return s
    if os.getenv("ALLOW_DEV_SECRET") == "1":
        return "dev-only-secret-change-me-0123456789abcdef"
    raise RuntimeError(
        "JWT_SECRET غير مضبوط. اضبطه في .env (أو ALLOW_DEV_SECRET=1 للتطوير فقط)."
    )


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"{salt.hex()}${h.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        salt_hex, hash_hex = stored.split("$")
        h = hashlib.scrypt(
            password.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1
        )
        return hmac.compare_digest(h.hex(), hash_hex)
    except Exception:
        return False


def make_token(user_id: int) -> str:
    now = int(time.time())
    payload = {"sub": str(user_id), "iat": now, "exp": now + TOKEN_DAYS * 86400}
    return jwt.encode(payload, _secret(), algorithm="HS256")


def decode_token(token: str) -> Optional[int]:
    try:
        data = jwt.decode(token, _secret(), algorithms=["HS256"])
        return int(data["sub"])
    except Exception:
        return None


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def make_reset_token() -> str:
    return secrets.token_urlsafe(32)


def current_user(creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer)):
    if creds is None:
        raise HTTPException(status_code=401, detail="سجّل الدخول أولاً")
    uid = decode_token(creds.credentials)
    user = db.get_user(uid) if uid is not None else None
    if user is None:
        raise HTTPException(
            status_code=401, detail="انتهت الجلسة، سجّل الدخول من جديد"
        )
    return user


def usage_info(user) -> dict:
    return {
        "email": user["email"],
        "plan": user["plan"],
        "used": db.usage_count(user["id"]),
        "limit": PLAN_LIMITS[user["plan"]],
    }


def require_quota(user) -> None:
    info = usage_info(user)
    if info["used"] >= info["limit"]:
        msg = (
            "انتهت ملخصاتك المجانية لهذا الشهر. اشترك للمتابعة."
            if user["plan"] == "free"
            else "بلغت حد الاستخدام الشهري لاشتراكك."
        )
        raise HTTPException(status_code=402, detail=msg)
