import os
from typing import List, Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from extract import ExtractError, extract_text
from summarizer import SummarizerError, summarize

MAX_FILE_MB = int(os.getenv("MAX_FILE_MB", "15"))
MAX_TEXT_CHARS = int(os.getenv("MAX_TEXT_CHARS", "200000"))

app = FastAPI(title="Mulakhis API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


def check_app_key(x_app_key: Optional[str] = Header(default=None)) -> None:
    """مفتاح بسيط بين التطبيق والخادم. اضبط APP_API_KEY لتفعيله."""
    expected = os.getenv("APP_API_KEY")
    if expected and x_app_key != expected:
        raise HTTPException(status_code=401, detail="غير مصرّح")


class Term(BaseModel):
    term: str
    definition: str


class SummaryResult(BaseModel):
    title: str
    summary: str
    key_points: List[str]
    terms: List[Term]
    source_chars: int


class TextRequest(BaseModel):
    text: str = Field(min_length=1)
    language: str = "ar"


def _run(text: str, language: str) -> SummaryResult:
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
    return SummaryResult(**data, source_chars=len(text))


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/summarize/text", response_model=SummaryResult, dependencies=[Depends(check_app_key)])
def summarize_text(req: TextRequest):
    return _run(req.text, req.language)


@app.post("/summarize/file", response_model=SummaryResult, dependencies=[Depends(check_app_key)])
async def summarize_file(file: UploadFile = File(...), language: str = Form("ar")):
    data = await file.read()
    if len(data) > MAX_FILE_MB * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"الملف أكبر من {MAX_FILE_MB} ميغابايت")
    try:
        text = extract_text(file.filename or "", data)
    except ExtractError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    return _run(text, language)
