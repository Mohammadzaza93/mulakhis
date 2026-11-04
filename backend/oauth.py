"""التحقق من رموز Google وApple Identity Token."""
import os
from typing import Any, Dict

import jwt
from jwt import PyJWKClient

GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs"
APPLE_CERTS = "https://appleid.apple.com/auth/keys"
GOOGLE_ISSUERS = {"https://accounts.google.com", "accounts.google.com"}
APPLE_ISSUER = "https://appleid.apple.com"


class OAuthError(Exception):
    pass


def _google_client_ids() -> list:
    raw = os.getenv("GOOGLE_CLIENT_IDS", os.getenv("GOOGLE_CLIENT_ID", ""))
    return [x.strip() for x in raw.split(",") if x.strip()]


def _apple_client_ids() -> list:
    raw = os.getenv("APPLE_CLIENT_IDS", os.getenv("APPLE_CLIENT_ID", ""))
    return [x.strip() for x in raw.split(",") if x.strip()]


def verify_google_id_token(token: str) -> Dict[str, Any]:
    if os.getenv("MOCK_AI") == "1" or os.getenv("ALLOW_DEV_SECRET") == "1":
        try:
            data = jwt.decode(token, options={"verify_signature": False})
            if data.get("email") and data.get("sub"):
                return {
                    "provider": "google",
                    "sub": str(data["sub"]),
                    "email": str(data["email"]).lower(),
                    "email_verified": bool(data.get("email_verified", True)),
                }
        except Exception:
            pass
        if token.startswith("dev-google:"):
            _, email, sub = token.split(":", 2)
            return {"provider": "google", "sub": sub, "email": email.lower(), "email_verified": True}

    client_ids = _google_client_ids()
    if not client_ids:
        raise OAuthError("GOOGLE_CLIENT_ID غير مضبوط على الخادم")
    try:
        jwks = PyJWKClient(GOOGLE_CERTS)
        key = jwks.get_signing_key_from_jwt(token)
        data = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            audience=client_ids,
            issuer=list(GOOGLE_ISSUERS),
            options={"verify_at_hash": False},
        )
    except Exception as e:
        raise OAuthError("رمز Google غير صالح") from e
    if not data.get("email"):
        raise OAuthError("رمز Google بلا بريد")
    if data.get("email_verified") is False:
        raise OAuthError("البريد غير موثّق لدى Google")
    return {
        "provider": "google",
        "sub": str(data["sub"]),
        "email": str(data["email"]).lower(),
        "email_verified": True,
    }


def verify_apple_id_token(token: str) -> Dict[str, Any]:
    if os.getenv("MOCK_AI") == "1" or os.getenv("ALLOW_DEV_SECRET") == "1":
        try:
            data = jwt.decode(token, options={"verify_signature": False})
            if data.get("sub"):
                email = data.get("email") or f"{data['sub']}@privaterelay.appleid.com"
                return {
                    "provider": "apple",
                    "sub": str(data["sub"]),
                    "email": str(email).lower(),
                    "email_verified": True,
                }
        except Exception:
            pass
        if token.startswith("dev-apple:"):
            _, email, sub = token.split(":", 2)
            return {"provider": "apple", "sub": sub, "email": email.lower(), "email_verified": True}

    client_ids = _apple_client_ids()
    if not client_ids:
        raise OAuthError("APPLE_CLIENT_ID غير مضبوط على الخادم")
    try:
        jwks = PyJWKClient(APPLE_CERTS)
        key = jwks.get_signing_key_from_jwt(token)
        data = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            audience=client_ids,
            issuer=APPLE_ISSUER,
            options={"verify_at_hash": False},
        )
    except Exception as e:
        raise OAuthError("رمز Apple غير صالح") from e
    email = data.get("email")
    if not email:
        email = f"{data['sub']}@privaterelay.appleid.com"
    return {
        "provider": "apple",
        "sub": str(data["sub"]),
        "email": str(email).lower(),
        "email_verified": True,
    }


def verify_oauth_token(provider: str, id_token: str) -> Dict[str, Any]:
    provider = (provider or "").lower().strip()
    if provider == "google":
        return verify_google_id_token(id_token)
    if provider == "apple":
        return verify_apple_id_token(id_token)
    raise OAuthError("مزوّد غير مدعوم (google أو apple)")
