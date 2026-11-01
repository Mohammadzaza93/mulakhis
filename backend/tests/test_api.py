import io
import os
import sys

os.environ["MOCK_AI"] = "1"
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402
from summarizer import parse_json_reply, split_text  # noqa: E402

client = TestClient(app)
SAMPLE = "الخلية هي الوحدة الأساسية للحياة. تحتوي الخلية على نواة. تنتج الميتوكوندريا الطاقة."


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_summarize_text():
    r = client.post("/summarize/text", json={"text": SAMPLE, "language": "ar"})
    assert r.status_code == 200
    body = r.json()
    assert body["summary"] and body["key_points"] and body["source_chars"] == len(SAMPLE)


def test_empty_text_rejected():
    assert client.post("/summarize/text", json={"text": ""}).status_code == 422


def test_txt_file():
    r = client.post(
        "/summarize/file",
        files={"file": ("a.txt", SAMPLE.encode("utf-8"), "text/plain")},
    )
    assert r.status_code == 200


def test_docx_file():
    from docx import Document

    buf = io.BytesIO()
    d = Document()
    d.add_paragraph(SAMPLE)
    d.save(buf)
    r = client.post("/summarize/file", files={"file": ("a.docx", buf.getvalue(), "application/octet-stream")})
    assert r.status_code == 200


def test_pdf_file():
    from reportlab.pdfgen import canvas

    buf = io.BytesIO()
    c = canvas.Canvas(buf)
    c.drawString(72, 750, "Cells are the basic unit of life. Mitochondria produce energy.")
    c.save()
    r = client.post("/summarize/file", files={"file": ("a.pdf", buf.getvalue(), "application/pdf")})
    assert r.status_code == 200, r.text


def test_unsupported_type():
    r = client.post("/summarize/file", files={"file": ("a.mp3", b"123", "audio/mpeg")})
    assert r.status_code == 415


def test_corrupt_pdf():
    r = client.post("/summarize/file", files={"file": ("a.pdf", b"not a pdf", "application/pdf")})
    assert r.status_code == 400


def test_app_key(monkeypatch):
    monkeypatch.setenv("APP_API_KEY", "secret")
    assert client.post("/summarize/text", json={"text": SAMPLE}).status_code == 401
    ok = client.post("/summarize/text", json={"text": SAMPLE}, headers={"X-App-Key": "secret"})
    assert ok.status_code == 200


def test_split_text():
    text = "\n\n".join(["فقرة " * 50] * 40)
    chunks = split_text(text, 1000)
    assert len(chunks) > 1 and all(len(c) <= 1000 for c in chunks)
    assert split_text("قصير", 1000) == ["قصير"]


def test_parse_json_reply():
    raw = '```json\n{"title":"ت","summary":"م","key_points":["أ"],"terms":[{"term":"ك","definition":"ع"}]}\n```'
    out = parse_json_reply(raw)
    assert out["title"] == "ت" and out["terms"][0]["term"] == "ك"
