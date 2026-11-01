"""استخراج النص من الملفات المدعومة: PDF وDOCX وTXT."""
import io
from typing import Tuple

SUPPORTED = (".pdf", ".docx", ".txt", ".md")


class ExtractError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


def extract_text(filename: str, data: bytes) -> str:
    name = (filename or "").lower()
    if name.endswith(".pdf"):
        text = _pdf(data)
    elif name.endswith(".docx"):
        text = _docx(data)
    elif name.endswith((".txt", ".md")):
        text = _plain(data)
    else:
        raise ExtractError(
            "نوع الملف غير مدعوم حالياً. المدعوم: PDF وDOCX وTXT.", status=415
        )
    text = text.strip()
    if not text:
        raise ExtractError(
            "لم أجد نصاً في الملف. إن كان ملفاً ممسوحاً ضوئياً فهو يحتاج OCR (غير مفعّل بعد)."
        )
    return text


def _pdf(data: bytes) -> str:
    from pypdf import PdfReader

    try:
        reader = PdfReader(io.BytesIO(data))
        if reader.is_encrypted:
            raise ExtractError("ملف PDF محمي بكلمة مرور")
        return "\n\n".join((p.extract_text() or "") for p in reader.pages)
    except ExtractError:
        raise
    except Exception as e:
        raise ExtractError("تعذّرت قراءة ملف PDF") from e


def _docx(data: bytes) -> str:
    from docx import Document

    try:
        doc = Document(io.BytesIO(data))
    except Exception as e:
        raise ExtractError("تعذّرت قراءة ملف Word") from e
    return "\n\n".join(p.text for p in doc.paragraphs if p.text.strip())


def _plain(data: bytes) -> str:
    for enc in ("utf-8", "utf-8-sig", "cp1256"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    raise ExtractError("تعذّر تحديد ترميز الملف النصي")
