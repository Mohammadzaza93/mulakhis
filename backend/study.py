"""توليد بطاقات مراجعة واختبار اختيار من متعدد من ملخص جاهز.

المصدر الوحيد للمعلومات هو الملخص المرسَل، حتى لا يخترع النموذج أسئلة من خارج المحاضرة.
"""
import os
import re
from typing import Any, Dict, List

from summarizer import LANG_NAMES, SummarizerError, _ask, _client, parse_json_object

MAX_CARDS = 12
MAX_QUESTIONS = 8

SYSTEM = (
    "أنت مدرّس يعدّ مواد مراجعة للطلاب. استخدم المعلومات الواردة في الملخص فقط ولا تضف من عندك. "
    "أعد كائن JSON واحداً فقط بدون أي شرح أو علامات ```، بالشكل: "
    '{"flashcards": [{"front": "سؤال أو مصطلح", "back": "إجابة مختصرة"}], '
    '"quiz": [{"question": "نص السؤال", "options": ["أ", "ب", "ج", "د"], '
    '"answer_index": 0, "explanation": "لماذا هذه الإجابة صحيحة"}]}. '
    "كل سؤال له أربعة خيارات بالضبط، واحد صحيح فقط، والخيارات الخاطئة معقولة وليست سخيفة، "
    "ولا يكون الخيار الصحيح دائماً في الموضع نفسه."
)


def _clean(s: Any) -> str:
    return re.sub(r"\s+", " ", str(s or "")).strip()


def validate_study(data: Dict[str, Any], max_cards: int, max_questions: int) -> Dict[str, List[Dict[str, Any]]]:
    """يُسقط أي عنصر معطوب بدل أن يُفشل الطلب كله، ويفشل فقط إن لم يبقَ شيء صالح."""
    cards = []
    for c in data.get("flashcards", []) or []:
        if not isinstance(c, dict):
            continue
        front, back = _clean(c.get("front")), _clean(c.get("back"))
        if front and back:
            cards.append({"front": front, "back": back})

    quiz = []
    for q in data.get("quiz", []) or []:
        if not isinstance(q, dict):
            continue
        question = _clean(q.get("question"))
        options = [_clean(o) for o in (q.get("options") or [])]
        idx = q.get("answer_index")
        if (
            not question
            or len(options) != 4
            or not all(options)
            or len(set(options)) != 4
            or not isinstance(idx, int)
            or isinstance(idx, bool)
            or not 0 <= idx < 4
        ):
            continue
        quiz.append(
            {
                "question": question,
                "options": options,
                "answer_index": idx,
                "explanation": _clean(q.get("explanation")),
            }
        )

    cards, quiz = cards[:max_cards], quiz[:max_questions]
    if not cards and not quiz:
        raise SummarizerError("لم يتمكن النموذج من إعداد مواد المراجعة، حاول مرة أخرى")
    return {"flashcards": cards, "quiz": quiz}


def _mock(material: str, max_cards: int, max_questions: int) -> Dict[str, Any]:
    sentences = [s.strip() for s in re.split(r"(?<=[.!؟?])\s+|\n", material) if len(s.strip()) > 10]
    cards = [{"front": f"ما المقصود بـ: {s[:30]}؟", "back": s} for s in sentences[:max_cards]]
    quiz = [
        {
            "question": f"أي مما يلي ورد في المحاضرة؟",
            "options": [s, "خيار خاطئ ١", "خيار خاطئ ٢", "خيار خاطئ ٣"],
            "answer_index": 0,
            "explanation": "ورد في الملخص.",
        }
        for s in sentences[:max_questions]
    ]
    return {"flashcards": cards, "quiz": quiz}


def generate_study(material: str, language: str = "ar", n_cards: int = 8, n_questions: int = 5) -> Dict[str, Any]:
    n_cards = max(1, min(n_cards, MAX_CARDS))
    n_questions = max(1, min(n_questions, MAX_QUESTIONS))
    material = material.strip()
    if not material:
        raise SummarizerError("لا يوجد ملخص لإعداد المراجعة منه")
    if os.getenv("MOCK_AI") == "1":
        return validate_study(_mock(material, n_cards, n_questions), n_cards, n_questions)

    lang = LANG_NAMES.get(language, LANG_NAMES["ar"])
    reply = _ask(
        _client(),
        SYSTEM,
        f"اللغة: {lang}\nعدد البطاقات: {n_cards}\nعدد أسئلة الاختبار: {n_questions}\n\nالملخص:\n{material}",
        3500,
    )
    return validate_study(parse_json_object(reply), n_cards, n_questions)
