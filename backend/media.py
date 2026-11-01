"""تحويل الصوت إلى نص (OpenAI Whisper API) وقراءة الصور (Claude vision).

كل شيء يعمل بوضع تجريبي عند MOCK_AI=1 بدون مفاتيح.
"""
import base64
import os
from typing import List, Optional, Tuple

import httpx

from summarizer import MODEL, SummarizerError, _client

AUDIO_EXT = (".mp3", ".m4a", ".wav", ".webm", ".ogg", ".aac", ".mp4", ".mpeg", ".mpga", ".flac")
IMAGE_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif"}
MAX_AUDIO_MB = 25  # حد خدمة Whisper
MAX_IMAGE_MB = 5  # حد صور Claude
MAX_IMAGES = 10

STT_URL = "https://api.openai.com/v1/audio/transcriptions"
STT_MODEL = os.getenv("STT_MODEL", "whisper-1")


def is_audio(filename: str) -> bool:
    return (filename or "").lower().endswith(AUDIO_EXT)


def image_media_type(filename: str) -> Optional[str]:
    name = (filename or "").lower()
    for ext, mt in IMAGE_TYPES.items():
        if name.endswith(ext):
            return mt
    return None


def transcribe(filename: str, data: bytes, language: Optional[str] = None) -> str:
    if os.getenv("MOCK_AI") == "1":
        return "هذا نص تجريبي ناتج عن تسجيل صوتي لمحاضرة عن الخلية. الخلية هي الوحدة الأساسية للحياة."
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise SummarizerError("مفتاح OPENAI_API_KEY غير مضبوط على الخادم")
    fields = {"model": STT_MODEL}
    if language in ("ar", "en"):
        fields["language"] = language
    try:
        r = httpx.post(
            STT_URL,
            headers={"Authorization": f"Bearer {key}"},
            data=fields,
            files={"file": (filename, data)},
            timeout=300,
        )
    except httpx.HTTPError as e:
        raise SummarizerError("تعذّر الاتصال بخدمة تحويل الصوت") from e
    if r.status_code != 200:
        raise SummarizerError("فشل تحويل الصوت إلى نص")
    text = (r.json().get("text") or "").strip()
    if not text:
        raise SummarizerError("لم أستطع سماع كلام واضح في التسجيل")
    return text


def ocr_images(images: List[Tuple[bytes, str]]) -> str:
    """يستخرج النص الظاهر في صور (صفحات كتاب أو سبورة أو شرائح)."""
    if os.getenv("MOCK_AI") == "1":
        return "نص تجريبي من الصورة. الميتوكوندريا تنتج الطاقة في الخلية."
    client = _client()
    content = []
    for data, media_type in images:
        content.append(
            {
                "type": "image",
                "source": {"type": "base64", "media_type": media_type, "data": base64.b64encode(data).decode()},
            }
        )
    content.append(
        {
            "type": "text",
            "text": (
                "انسخ كل النص الظاهر في هذه الصور حرفياً وبنفس لغته وترتيبه (من الصورة الأولى إلى الأخيرة)، "
                "بدون أي تعليق أو شرح. إن لم يوجد أي نص مقروء اكتب كلمة EMPTY فقط."
            ),
        }
    )
    msg = client.messages.create(
        model=MODEL, max_tokens=4000, messages=[{"role": "user", "content": content}]
    )
    text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text").strip()
    if not text or text == "EMPTY":
        raise SummarizerError("لم أجد نصاً مقروءاً في الصور")
    return text
