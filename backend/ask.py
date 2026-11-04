"""اسأل ملفك: إجابة أسئلة من ملخص/نص أصلي فقط دون اختراع معلومات."""
import os
import re
from typing import Any, Dict

from summarizer import LANG_NAMES, SummarizerError, _ask, _client, parse_json_object

SYSTEM = (
    "أنت مساعد دراسي يجيب من المحتوى المقدَّم فقط. "
    "إن لم تكن الإجابة موجودة بوضوح في المحتوى فقل ذلك صراحة ولا تخمّن. "
    "أعد كائن JSON واحداً فقط بدون شرح أو علامات ```، بالشكل: "
    '{"answer": "الإجابة المختصرة والواضحة", "grounded": true, '
    '"citations": ["اقتباس قصير من المصدر يدعم الإجابة"]}. '
    "grounded=false إن لم تجد الإجابة في المحتوى، وفي هذه الحالة اجعل answer توضيحاً قصيراً أن المعلومة غير موجودة."
)


def _mock(question: str, material: str) -> Dict[str, Any]:
    q = question.strip()
    words = [w for w in re.split(r"\s+", q) if len(w) > 2]
    hits = [s.strip() for s in re.split(r"[.!?\u061f\n]+", material) if any(w in s for w in words)]
    if hits:
        return {
            "answer": hits[0][:300],
            "grounded": True,
            "citations": hits[:2],
        }
    return {
        "answer": "لم أجد هذه المعلومة في محتوى الملخص أو النص الأصلي.",
        "grounded": False,
        "citations": [],
    }


def ask(material: str, question: str, language: str = "ar") -> Dict[str, Any]:
    material = (material or "").strip()
    question = (question or "").strip()
    if not material:
        raise SummarizerError("لا يوجد محتوى للإجابة منه")
    if not question:
        raise SummarizerError("السؤال فارغ")
    if len(question) > 500:
        raise SummarizerError("السؤال طويل جداً")
    if len(material) > 100_000:
        material = material[:100_000]

    if os.getenv("MOCK_AI") == "1":
        return _mock(question, material)

    lang = LANG_NAMES.get(language, LANG_NAMES["ar"])
    reply = _ask(
        _client(),
        SYSTEM,
        f"اللغة: {lang}\n\nالسؤال:\n{question}\n\nالمحتوى:\n{material}",
        1500,
    )
    data = parse_json_object(reply)
    answer = str(data.get("answer") or "").strip()
    if not answer:
        raise SummarizerError("تعذّر توليد إجابة")
    grounded = bool(data.get("grounded", True))
    citations_raw = data.get("citations")
    citations = []
    if isinstance(citations_raw, list):
        citations = [str(c).strip() for c in citations_raw if str(c).strip()][:5]
    return {"answer": answer, "grounded": grounded, "citations": citations}
