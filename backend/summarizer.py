"""منطق التلخيص: تقسيم النص الطويل، استدعاء Claude، وتحويل الناتج إلى JSON منظّم.

يعمل بوضع تجريبي (MOCK_AI=1) بدون مفتاح، لأغراض الاختبار والتطوير فقط.
"""
import json
import os
import re
from typing import Any, Dict, List

CHUNK_CHARS = int(os.getenv("CHUNK_CHARS", "12000"))
MODEL = os.getenv("SUMMARY_MODEL", "claude-haiku-5-5")

LANG_NAMES = {"ar": "العربية", "en": "English"}

FINAL_SYSTEM = (
    "أنت مساعد دراسي يلخّص المحاضرات للطلاب بدقة. "
    "لا تضف معلومات غير موجودة في النص. "
    "أعد الناتج كائن JSON واحداً فقط، بدون أي شرح أو علامات ```، بالشكل: "
    '{"title": "عنوان قصير", "summary": "ملخص متماسك في فقرتين أو ثلاث", '
    '"key_points": ["نقطة", "..."], '
    '"terms": [{"term": "مصطلح", "definition": "تعريف مختصر"}]} '
    "عدد النقاط من 5 إلى 10، والمصطلحات من 0 إلى 8."
)

CHUNK_SYSTEM = (
    "أنت مساعد دراسي. استخرج من الجزء التالي من محاضرة ملاحظات مركّزة "
    "(حقائق، تعريفات، أمثلة مهمة) على شكل نقاط قصيرة، بدون إضافة معلومات من عندك."
)


class SummarizerError(Exception):
    pass


def split_text(text: str, size: int = CHUNK_CHARS) -> List[str]:
    """يقسّم النص عند حدود الفقرات قدر الإمكان."""
    text = text.strip()
    if len(text) <= size:
        return [text]
    chunks: List[str] = []
    current = ""
    for para in re.split(r"\n\s*\n", text):
        if len(para) > size:  # فقرة ضخمة: قص بالقوة
            if current:
                chunks.append(current)
                current = ""
            for i in range(0, len(para), size):
                chunks.append(para[i : i + size])
            continue
        if len(current) + len(para) + 2 > size and current:
            chunks.append(current)
            current = para
        else:
            current = f"{current}\n\n{para}" if current else para
    if current:
        chunks.append(current)
    return chunks


def parse_json_object(raw: str) -> Dict[str, Any]:
    """يستخرج كائن JSON من رد النموذج حتى لو أحاطه بعلامات أو شرح."""
    raw = raw.strip()
    raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)
    start, end = raw.find("{"), raw.rfind("}")
    if start == -1 or end == -1:
        raise SummarizerError("تعذّر قراءة رد النموذج")
    try:
        data = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as e:
        raise SummarizerError("رد النموذج ليس JSON صالحاً") from e
    if not isinstance(data, dict):
        raise SummarizerError("رد النموذج ليس بالشكل المتوقع")
    return data


def _as_text(value: Any) -> str:
    """يحوّل قيمة من رد النموذج إلى نص نظيف دون أن يفشل على None أو الأنواع الغريبة."""
    return "" if value is None else str(value).strip()


def _as_text_list(value: Any) -> List[str]:
    """يقبل قائمة نصوص فقط، وأي شكل آخر (نص أو None) يعطي قائمة فارغة."""
    if not isinstance(value, list):
        return []
    return [_as_text(p) for p in value if _as_text(p)]


def parse_json_reply(raw: str) -> Dict[str, Any]:
    data = parse_json_object(raw)
    terms = data.get("terms")
    if not isinstance(terms, list):
        terms = []
    return {
        "title": _as_text(data.get("title")) or "ملخص جديد",
        "summary": _as_text(data.get("summary")),
        "key_points": _as_text_list(data.get("key_points")),
        "terms": [
            {"term": _as_text(t.get("term")), "definition": _as_text(t.get("definition"))}
            for t in terms
            if isinstance(t, dict) and _as_text(t.get("term"))
        ],
    }


def _mock_summary(text: str) -> Dict[str, Any]:
    sentences = [s.strip() for s in re.split(r"(?<=[.!؟?])\s+", text) if s.strip()]
    first = sentences[:3] or [text[:200]]
    return {
        "title": (sentences[0][:40] if sentences else "ملخص تجريبي"),
        "summary": " ".join(first),
        "key_points": sentences[:5],
        "terms": [],
    }


def _client():
    import anthropic

    key = os.getenv("ANTHROPIC_API_KEY")
    if not key:
        raise SummarizerError("مفتاح ANTHROPIC_API_KEY غير مضبوط على الخادم")
    return anthropic.Anthropic(api_key=key, max_retries=3, timeout=120)


def _ask(client, system: str, user: str, max_tokens: int) -> str:
    msg = client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")


def summarize(text: str, language: str = "ar") -> Dict[str, Any]:
    text = text.strip()
    if not text:
        raise SummarizerError("النص فارغ")
    if os.getenv("MOCK_AI") == "1":
        return _mock_summary(text)

    lang = LANG_NAMES.get(language, LANG_NAMES["ar"])
    client = _client()
    chunks = split_text(text)

    if len(chunks) == 1:
        material = chunks[0]
    else:
        notes = [
            _ask(client, CHUNK_SYSTEM, f"الجزء {i + 1} من {len(chunks)}:\n\n{c}", 1500)
            for i, c in enumerate(chunks)
        ]
        material = "\n\n".join(notes)

    reply = _ask(
        client,
        FINAL_SYSTEM,
        f"اكتب الملخص بلغة: {lang}\n\nالنص:\n{material}",
        2500,
    )
    return parse_json_reply(reply)
