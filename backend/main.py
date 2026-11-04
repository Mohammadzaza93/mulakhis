import os
from typing import List, Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import db
import media
import security
import study
from extract import ExtractError, extract_text
from summarizer import SummarizerError, summarize

MAX_FILE_MB = int(os.getenv("MAX_FILE_MB", "15"))
MAX_TEXT_CHARS = int(os.getenv("MAX_TEXT_CHARS", "200000"))

app = FastAPI(title="Mulakhis API", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------- نماذج ----------
class Term(BaseModel):
    term: str
    definition: str


class SummaryResult(BaseModel):
    title: str
    summary: str
    key_points: List[str]
    terms: List[Term]
    source_chars: int
    transcript: Optional[str] = None  # نص الصوت أو الصور المستخرج


class TextRequest(BaseModel):
    text: str = Field(min_length=1)
    language: str = "ar"


class Credentials(BaseModel):
    email: str
    password: str


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


# ---------- أدوات ----------
def _auth_result(user_id: int) -> AuthResult:
    user = db.get_user(user_id)
    info = security.usage_info(user)
    return AuthResult(token=security.make_token(user_id), user_id=user_id, **info)


def _run(user, text: str, language: str, transcript: Optional[str] = None) -> SummaryResult:
    text = text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="النص فارغ")
    if len(text) > MAX_TEXT_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"النص طويل جداً (الحد {MAX_TEXT_CHARS} حرفاً). قسّمه إلى أجزاء.",
        )
    try:
        data = summarize(text, language)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="تعذّر الاتصال بخدمة التلخيص، حاول لاحقاً")
    db.add_usage(user["id"])  # لا يُحتسب إلا عند النجاح
    return SummaryResult(**data, source_chars=len(text), transcript=transcript)


async def _read_limited(f: UploadFile, max_mb: int, what: str) -> bytes:
    data = await f.read()
    if len(data) > max_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"{what} أكبر من {max_mb} ميغابايت")
    if not data:
        raise HTTPException(status_code=400, detail=f"{what} فارغ")
    return data


# ---------- عام ----------
@app.get("/health")
def health():
    return {"status": "ok"}


# ---------- الحسابات ----------
@app.post("/auth/register", response_model=AuthResult)
def register(c: Credentials):
    email = c.email.strip().lower()
    if not security.EMAIL_RE.match(email):
        raise HTTPException(status_code=422, detail="البريد الإلكتروني غير صالح")
    if len(c.password) < 8:
        raise HTTPException(status_code=422, detail="كلمة المرور يجب ألا تقل عن 8 أحرف")
    try:
        uid = db.create_user(email, security.hash_password(c.password))
    except ValueError:
        raise HTTPException(status_code=409, detail="هذا البريد مسجّل مسبقاً")
    return _auth_result(uid)


@app.post("/auth/login", response_model=AuthResult)
def login(c: Credentials):
    user = db.get_user_by_email(c.email.strip().lower())
    if user is None or not security.verify_password(c.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="البريد أو كلمة المرور غير صحيحة")
    return _auth_result(user["id"])


@app.get("/me", response_model=Me)
def me(user=Depends(security.current_user)):
    return Me(user_id=user["id"], **security.usage_info(user))


# ---------- التلخيص ----------
@app.post("/summarize/text", response_model=SummaryResult)
def summarize_text(req: TextRequest, user=Depends(security.current_user)):
    security.require_quota(user)
    return _run(user, req.text, req.language)


@app.post("/summarize/file", response_model=SummaryResult)
async def summarize_file(
    file: UploadFile = File(...), language: str = Form("ar"), user=Depends(security.current_user)
):
    security.require_quota(user)
    data = await _read_limited(file, MAX_FILE_MB, "الملف")
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
        raise HTTPException(status_code=415, detail="صيغة الصوت غير مدعومة (المدعوم: mp3 وm4a وwav وwebm وogg وaac)")
    data = await _read_limited(file, media.MAX_AUDIO_MB, "ملف الصوت")
    try:
        text = await run_in_threadpool(media.transcribe, file.filename or "audio", data, language)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="تعذّر الاتصال بخدمة تحويل الصوت، حاول لاحقاً")
    return await run_in_threadpool(_run, user, text, language, text)


@app.post("/summarize/image", response_model=SummaryResult)
async def summarize_images(
    files: List[UploadFile] = File(...), language: str = Form("ar"), user=Depends(security.current_user)
):
    security.require_quota(user)
    if len(files) > media.MAX_IMAGES:
        raise HTTPException(status_code=413, detail=f"الحد الأقصى {media.MAX_IMAGES} صور في المرة الواحدة")
    images = []
    for f in files:
        mt = media.image_media_type(f.filename or "")
        if mt is None:
            raise HTTPException(status_code=415, detail="صيغة الصورة غير مدعومة (المدعوم: jpg وpng وwebp)")
        images.append((await _read_limited(f, media.MAX_IMAGE_MB, "الصورة"), mt))
    try:
        text = await run_in_threadpool(media.ocr_images, images)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="تعذّرت قراءة الصور، حاول لاحقاً")
    return await run_in_threadpool(_run, user, text, language, text)


# ---------- المراجعة: بطاقات واختبارات ----------
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
    """يحتسب كملخص واحد من الحصة الشهرية، ولا يُحتسب إلا عند النجاح."""
    security.require_quota(user)
    summary = req.summary.strip()
    if not summary:
        raise HTTPException(status_code=422, detail="الملخص فارغ")
    parts = [summary]
    if req.key_points:
        parts.append("النقاط الرئيسية:\n" + "\n".join(f"- {p}" for p in req.key_points))
    if req.terms:
        parts.append("المصطلحات:\n" + "\n".join(f"- {t.term}: {t.definition}" for t in req.terms))
    try:
        data = study.generate_study("\n\n".join(parts), req.language, req.cards, req.questions)
    except SummarizerError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="تعذّر الاتصال بخدمة الذكاء الاصطناعي، حاول لاحقاً")
    db.add_usage(user["id"])
    return data


# ---------- الاشتراكات (RevenueCat) ----------
_PRO_EVENTS = {"INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "NON_RENEWING_PURCHASE"}
_FREE_EVENTS = {"EXPIRATION"}  # CANCELLATION يبقى فعّالاً حتى انتهاء المدة


@app.post("/webhooks/revenuecat")
def revenuecat_webhook(payload: dict, authorization: Optional[str] = Header(default=None)):
    """يضبط RevenueCat هذا الرابط مع رأس Authorization بقيمة REVENUECAT_WEBHOOK_AUTH."""
    expected = os.getenv("REVENUECAT_WEBHOOK_AUTH")
    if not expected or authorization != expected:
        raise HTTPException(status_code=401, detail="غير مصرّح")
    event = payload.get("event") or {}
    etype, app_user_id = event.get("type"), str(event.get("app_user_id", ""))
    if not app_user_id.isdigit():
        return {"ok": True, "ignored": "unknown user"}
    if etype in _PRO_EVENTS:
        db.set_plan(int(app_user_id), "pro")
    elif etype in _FREE_EVENTS:
        db.set_plan(int(app_user_id), "free")
    return {"ok": True}
