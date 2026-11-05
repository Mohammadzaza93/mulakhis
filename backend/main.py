import os
import smtplib
import time
from email.message import EmailMessage
from typing import List, Optional

from fastapi import Body, Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import ask
import db
import media
import oauth
import security
import study
from extract import ExtractError, extract_text
from rate_limit import RateLimitMiddleware
from summarizer import SummarizerError, summarize

MAX_FILE_MB = int(os.getenv("MAX_FILE_MB", "15"))
MAX_TEXT_CHARS = int(os.getenv("MAX_TEXT_CHARS", "200000"))

app = FastAPI(title="Mulakhis API", version="0.3.0")
app.add_middleware(RateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


class Term(BaseModel):
    term: str
    definition: str


class SummaryResult(BaseModel):
    title: str
    summary: str
    key_points: List[str]
    terms: List[Term]
    source_chars: int
    transcript: Optional[str] = None


class TextRequest(BaseModel):
    text: str = Field(min_length=1)
    language: str = "ar"


class Credentials(BaseModel):
    email: str
    password: str


class OAuthRequest(BaseModel):
    provider: str
    id_token: str


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


class AuthResult(BaseModel):
    token: str
    user_id: int
    email: str
    plan: str
    used: int
    limit: int


class Me(BaseModel):
    user_id: int
    email: str
    plan: str
    used: int
    limit: int


class AskRequest(BaseModel):
    summary: str = ""
    transcript: Optional[str] = None
    question: str = Field(min_length=1, max_length=500)
    language: str = "ar"


class AskResult(BaseModel):
    answer: str
    grounded: bool
    citations: List[str]


class LibraryItem(BaseModel):
    id: str = Field(min_length=1)
    title: str = "\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f"
    summary: str = ""
    key_points: List[str] = Field(default_factory=list)
    terms: List[dict] = Field(default_factory=list)
    language: str = "ar"
    transcript: Optional[str] = None
    study: Optional[dict] = None
    created_at: int = 0
    updated_at: int = 0


class LibrarySyncRequest(BaseModel):
    items: List[LibraryItem] = Field(default_factory=list)


def _auth_result(user_id: int) -> AuthResult:
    user = db.get_user(user_id)
    info = security.usage_info(user)
    return AuthResult(token=security.make_token(user_id), user_id=user_id, **info)


def _run(user, text: str, language: str, transcript: Optional[str] = None) -> SummaryResult:
    text = text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="\u0627\u0644\u0646\u0635 \u0641\u0627\u0631\u063a")
    if len(text) > MAX_TEXT_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"\u0627\u0644\u0646\u0635 \u0637\u0648\u064a\u0644 \u062c\u062f\u0627\u064b (\u0627\u0644\u062d\u062f {MAX_TEXT_CHARS} \u062d\u0631\u0641\u0627\u064b). \u0642\u0633\u0651\u0645\u0647 \u0625\u0644\u0649 \u0623\u062c\u0632\u0627\u0621.",
        )
    try:
        data = summarize(text, language)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="\u062a\u0639\u0630\u0651\u0631 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u0628\u062e\u062f\u0645\u0629 \u0627\u0644\u062a\u0644\u062e\u064a\u0635\u060c \u062d\u0627\u0648\u0644 \u0644\u0627\u062d\u0642\u0627\u064b")
    db.add_usage(user["id"])
    return SummaryResult(**data, source_chars=len(text), transcript=transcript)


async def _read_limited(f: UploadFile, max_mb: int, what: str) -> bytes:
    data = await f.read()
    if len(data) > max_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"{what} \u0623\u0643\u0628\u0631 \u0645\u0646 {max_mb} \u0645\u064a\u063a\u0627\u0628\u0627\u064a\u062a")
    if not data:
        raise HTTPException(status_code=400, detail=f"{what} \u0641\u0627\u0631\u063a")
    return data


def _clean_email(email: str) -> str:
    return (email or "").strip().lower()


def _valid_email(email: str) -> bool:
    if not email or len(email) > 254 or any(ch.isspace() for ch in email):
        return False
    if email.count("@") != 1:
        return False
    local, domain = email.split("@", 1)
    if not local or "." not in domain:
        return False
    if domain.startswith(".") or domain.endswith("."):
        return False
    return True


def _send_reset_email(email: str, token: str) -> None:
    host = os.getenv("SMTP_HOST")
    port = int(os.getenv("SMTP_PORT", "587"))
    user = os.getenv("SMTP_USER")
    password = os.getenv("SMTP_PASSWORD")
    from_email = os.getenv("SMTP_FROM")
    app_url = os.getenv("APP_URL", "")
    if not host or not from_email:
        return
    reset_url = f"{app_url.rstrip('/')}/reset-password?token={token}" if app_url else token
    msg = EmailMessage()
    msg["Subject"] = "Mulakhis - Password reset"
    msg["From"] = from_email
    msg["To"] = email
    msg.set_content(
        "\u0637\u0644\u0628\u062a \u0625\u0639\u0627\u062f\u0629 \u062a\u0639\u064a\u064a\u0646 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631.\n"
        f"\u0627\u0633\u062a\u062e\u062f\u0645 \u0647\u0630\u0627 \u0627\u0644\u0631\u0627\u0628\u0637 \u0623\u0648 \u0627\u0644\u0631\u0645\u0632 \u062e\u0644\u0627\u0644 {security.RESET_TOKEN_HOURS} \u0633\u0627\u0639\u0629:\n{reset_url}\n"
        "\u0625\u0630\u0627 \u0644\u0645 \u062a\u0637\u0644\u0628 \u0630\u0644\u0643 \u0641\u062a\u062c\u0627\u0647\u0644 \u0627\u0644\u0631\u0633\u0627\u0644\u0629."
    )
    with smtplib.SMTP(host, port, timeout=20) as server:
        if os.getenv("SMTP_TLS", "1") != "0":
            server.starttls()
        if user and password:
            server.login(user, password)
        server.send_message(msg)


def _normalize_library_item(payload: dict) -> dict:
    now = int(time.time())
    key_points = payload.get("key_points")
    if key_points is None:
        key_points = payload.get("keyPoints")
    terms = payload.get("terms")
    return {
        "id": str(payload.get("id") or "").strip(),
        "title": str(payload.get("title") or "\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f").strip() or "\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f",
        "summary": str(payload.get("summary") or ""),
        "key_points": [str(x) for x in (key_points or [])],
        "terms": [dict(x) for x in (terms or []) if isinstance(x, dict)],
        "language": str(payload.get("language") or "ar"),
        "transcript": payload.get("transcript"),
        "study": payload.get("study") if isinstance(payload.get("study"), dict) else None,
        "created_at": int(payload.get("created_at") or payload.get("createdAt") or now),
        "updated_at": int(payload.get("updated_at") or payload.get("updatedAt") or now),
    }


def _library_out(item: dict) -> dict:
    return {
        "id": item["id"],
        "title": item.get("title") or "\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f",
        "summary": item.get("summary") or "",
        "key_points": item.get("key_points") or [],
        "terms": item.get("terms") or [],
        "language": item.get("language") or "ar",
        "transcript": item.get("transcript"),
        "study": item.get("study"),
        "created_at": int(item.get("created_at") or int(time.time())),
        "updated_at": int(item.get("updated_at") or int(time.time())),
    }


def _model_data(model: BaseModel) -> dict:
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/register", response_model=AuthResult)
def register(c: Credentials):
    email = _clean_email(c.email)
    if not _valid_email(email):
        raise HTTPException(status_code=422, detail="\u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u0625\u0644\u0643\u062a\u0631\u0648\u0646\u064a \u063a\u064a\u0631 \u0635\u0627\u0644\u062d")
    if len(c.password) < 8:
        raise HTTPException(status_code=422, detail="\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u064a\u062c\u0628 \u0623\u0644\u0627 \u062a\u0642\u0644 \u0639\u0646 8 \u0623\u062d\u0631\u0641")
    try:
        uid = db.create_user(email, security.hash_password(c.password))
    except ValueError:
        raise HTTPException(status_code=409, detail="\u0647\u0630\u0627 \u0627\u0644\u0628\u0631\u064a\u062f \u0645\u0633\u062c\u0651\u0644 \u0645\u0633\u0628\u0642\u0627\u064b")
    return _auth_result(uid)


@app.post("/auth/login", response_model=AuthResult)
def login(c: Credentials):
    user = db.get_user_by_email(_clean_email(c.email))
    if user is None or not user["password_hash"] or not security.verify_password(c.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="\u0627\u0644\u0628\u0631\u064a\u062f \u0623\u0648 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d\u0629")
    return _auth_result(user["id"])


@app.post("/auth/oauth", response_model=AuthResult)
def auth_oauth(req: OAuthRequest):
    try:
        claims = oauth.verify_oauth_token(req.provider, req.id_token)
    except oauth.OAuthError as e:
        raise HTTPException(status_code=400, detail=str(e))
    uid = db.get_or_create_oauth_user(claims["provider"], claims["sub"], claims["email"])
    return _auth_result(uid)


@app.post("/auth/forgot-password")
def forgot_password(req: ForgotPasswordRequest):
    email = _clean_email(req.email)
    if _valid_email(email):
        user = db.get_user_by_email(email)
        if user:
            token = security.make_reset_token()
            db.create_password_reset(
                int(user["id"]),
                security.hash_token(token),
                int(time.time()) + security.RESET_TOKEN_HOURS * 3600,
            )
            try:
                _send_reset_email(email, token)
            except Exception:
                pass
            if os.getenv("MOCK_AI") == "1":
                return {"ok": True, "dev_token": token}
    return {"ok": True}


@app.post("/auth/reset-password")
def reset_password(req: ResetPasswordRequest):
    if len(req.new_password) < 8:
        raise HTTPException(status_code=422, detail="\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u064a\u062c\u0628 \u0623\u0644\u0627 \u062a\u0642\u0644 \u0639\u0646 8 \u0623\u062d\u0631\u0641")
    rec = db.get_password_reset(security.hash_token(req.token))
    if rec is None or rec["used_at"] is not None or int(rec["expires_at"]) < int(time.time()):
        raise HTTPException(status_code=400, detail="\u0631\u0627\u0628\u0637 \u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u062a\u0639\u064a\u064a\u0646 \u063a\u064a\u0631 \u0635\u0627\u0644\u062d \u0623\u0648 \u0645\u0646\u062a\u0647\u064a")
    db.set_password(int(rec["user_id"]), security.hash_password(req.new_password))
    db.mark_password_reset_used(int(rec["id"]))
    return {"ok": True}


@app.get("/me", response_model=Me)
def me(user=Depends(security.current_user)):
    return Me(user_id=user["id"], **security.usage_info(user))


@app.delete("/me")
def delete_me(user=Depends(security.current_user)):
    db.delete_user(int(user["id"]))
    return {"ok": True}


@app.post("/summarize/text", response_model=SummaryResult)
def summarize_text(req: TextRequest, user=Depends(security.current_user)):
    security.require_quota(user)
    return _run(user, req.text, req.language)


@app.post("/summarize/file", response_model=SummaryResult)
async def summarize_file(
    file: UploadFile = File(...), language: str = Form("ar"), user=Depends(security.current_user)
):
    security.require_quota(user)
    data = await _read_limited(file, MAX_FILE_MB, "\u0627\u0644\u0645\u0644\u0641")
    try:
        text = await run_in_threadpool(extract_text, file.filename or "", data)
    except ExtractError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    return await run_in_threadpool(_run, user, text, language)


@app.post("/summarize/audio", response_model=SummaryResult)
async def summarize_audio(
    file: UploadFile = File(...), language: str = Form("ar"), user=Depends(security.current_user)
):
    security.require_quota(user)
    if not media.is_audio(file.filename or ""):
        raise HTTPException(status_code=415, detail="\u0635\u064a\u063a\u0629 \u0627\u0644\u0635\u0648\u062a \u063a\u064a\u0631 \u0645\u062f\u0639\u0648\u0645\u0629")
    data = await _read_limited(file, media.MAX_AUDIO_MB, "\u0645\u0644\u0641 \u0627\u0644\u0635\u0648\u062a")
    try:
        text = await run_in_threadpool(media.transcribe, file.filename or "audio", data, language)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="\u062a\u0639\u0630\u0651\u0631 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u0628\u062e\u062f\u0645\u0629 \u062a\u062d\u0648\u064a\u0644 \u0627\u0644\u0635\u0648\u062a")
    return await run_in_threadpool(_run, user, text, language, text)


@app.post("/summarize/image", response_model=SummaryResult)
async def summarize_images(
    files: List[UploadFile] = File(...), language: str = Form("ar"), user=Depends(security.current_user)
):
    security.require_quota(user)
    if len(files) > media.MAX_IMAGES:
        raise HTTPException(status_code=413, detail=f"\u0627\u0644\u062d\u062f \u0627\u0644\u0623\u0642\u0635\u0649 {media.MAX_IMAGES} \u0635\u0648\u0631")
    images = []
    for f in files:
        mt = media.image_media_type(f.filename or "")
        if mt is None:
            raise HTTPException(status_code=415, detail="\u0635\u064a\u063a\u0629 \u0627\u0644\u0635\u0648\u0631\u0629 \u063a\u064a\u0631 \u0645\u062f\u0639\u0648\u0645\u0629")
        images.append((await _read_limited(f, media.MAX_IMAGE_MB, "\u0627\u0644\u0635\u0648\u0631\u0629"), mt))
    try:
        text = await run_in_threadpool(media.ocr_images, images)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="\u062a\u0639\u0630\u0651\u0631\u062a \u0642\u0631\u0627\u0621\u0629 \u0627\u0644\u0635\u0648\u0631")
    return await run_in_threadpool(_run, user, text, language, text)


@app.post("/ask", response_model=AskResult)
def ask_material(req: AskRequest, user=Depends(security.current_user)):
    material = "\n\n".join(
        [x.strip() for x in [req.summary, req.transcript or ""] if x and x.strip()]
    )
    if not material:
        raise HTTPException(status_code=422, detail="\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u062d\u062a\u0648\u0649 \u0644\u0644\u0625\u062c\u0627\u0628\u0629 \u0645\u0646\u0647")
    try:
        data = ask.ask(material, req.question, req.language)
    except SummarizerError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="\u062a\u0639\u0630\u0651\u0631 \u0627\u0644\u062d\u0635\u0648\u0644 \u0639\u0644\u0649 \u0625\u062c\u0627\u0628\u0629 \u0627\u0644\u0622\u0646")
    return AskResult(**data)


class StudyRequest(BaseModel):
    summary: str = Field(min_length=1, max_length=20000)
    key_points: List[str] = Field(default_factory=list, max_length=30)
    terms: List[Term] = Field(default_factory=list, max_length=30)
    language: str = "ar"
    cards: int = Field(default=8, ge=1, le=study.MAX_CARDS)
    questions: int = Field(default=5, ge=1, le=study.MAX_QUESTIONS)


class Flashcard(BaseModel):
    front: str
    back: str


class QuizQuestion(BaseModel):
    question: str
    options: List[str]
    answer_index: int
    explanation: str = ""


class StudyResult(BaseModel):
    flashcards: List[Flashcard]
    quiz: List[QuizQuestion]


@app.post("/study/generate", response_model=StudyResult)
def generate_study(req: StudyRequest, user=Depends(security.current_user)):
    security.require_quota(user)
    summary = req.summary.strip()
    if not summary:
        raise HTTPException(status_code=422, detail="\u0627\u0644\u0645\u0644\u062e\u0635 \u0641\u0627\u0631\u063a")
    parts = [summary]
    if req.key_points:
        parts.append("\u0627\u0644\u0646\u0642\u0627\u0637 \u0627\u0644\u0631\u0626\u064a\u0633\u064a\u0629:\n" + "\n".join(f"- {p}" for p in req.key_points))
    if req.terms:
        parts.append("\u0627\u0644\u0645\u0635\u0637\u0644\u062d\u0627\u062a:\n" + "\n".join(f"- {t.term}: {t.definition}" for t in req.terms))
    try:
        data = study.generate_study("\n\n".join(parts), req.language, req.cards, req.questions)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="\u062a\u0639\u0630\u0651\u0631 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u0628\u062e\u062f\u0645\u0629 \u0627\u0644\u0630\u0643\u0627\u0621 \u0627\u0644\u0627\u0635\u0637\u0646\u0627\u0639\u064a")
    db.add_usage(user["id"])
    return data


@app.get("/library")
def get_library(user=Depends(security.current_user)):
    return [_library_out(x) for x in db.list_summaries(int(user["id"]))]


@app.put("/library")
def put_library(item: LibraryItem, user=Depends(security.current_user)):
    data = db.upsert_summary(int(user["id"]), _normalize_library_item(_model_data(item)))
    return _library_out(data)


@app.delete("/library/{summary_id}")
def delete_library_item(summary_id: str, user=Depends(security.current_user)):
    deleted = db.delete_summary(int(user["id"]), summary_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="\u0627\u0644\u0639\u0646\u0635\u0631 \u063a\u064a\u0631 \u0645\u0648\u062c\u0648\u062f")
    return {"ok": True}


@app.post("/library/sync")
def sync_library(req: LibrarySyncRequest = Body(default=LibrarySyncRequest()), user=Depends(security.current_user)):
    uid = int(user["id"])
    for item in req.items:
        normalized = _normalize_library_item(_model_data(item))
        if not normalized["id"]:
            continue
        existing = db.get_summary(uid, normalized["id"])
        if existing is None or int(normalized["updated_at"]) >= int(existing["updated_at"]):
            db.upsert_summary(uid, normalized)
    return [_library_out(x) for x in db.list_summaries(uid)]


_PRO_EVENTS = {"INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "NON_RENEWING_PURCHASE"}
_FREE_EVENTS = {"EXPIRATION"}


@app.post("/webhooks/revenuecat")
def revenuecat_webhook(payload: dict, authorization: Optional[str] = Header(default=None)):
    expected = os.getenv("REVENUECAT_WEBHOOK_AUTH")
    if not expected or authorization != expected:
        raise HTTPException(status_code=401, detail="\u063a\u064a\u0631 \u0645\u0635\u0631\u0651\u062d")
    event = payload.get("event") or {}
    etype, app_user_id = event.get("type"), str(event.get("app_user_id", ""))
    if not app_user_id.isdigit():
        return {"ok": True, "ignored": "unknown user"}
    if etype in _PRO_EVENTS:
        db.set_plan(int(app_user_id), "pro")
    elif etype in _FREE_EVENTS:
        db.set_plan(int(app_user_id), "free")
    return {"ok": True}
