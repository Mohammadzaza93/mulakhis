import io
import os
import sys

os.environ["MOCK_AI"] = "1"
os.environ["JWT_SECRET"] = "test-secret-0123456789abcdef0123456789"
os.environ["REVENUECAT_WEBHOOK_AUTH"] = "rc-secret"
os.environ["RATE_LIMIT_AUTH"] = "100000"
os.environ["RATE_LIMIT_GENERAL"] = "100000"
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest  # noqa: E402
import jwt  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import media  # noqa: E402
import security  # noqa: E402
import study  # noqa: E402
from main import app  # noqa: E402
from summarizer import SummarizerError, parse_json_reply, split_text  # noqa: E402

SAMPLE = "الخلية هي الوحدة الأساسية للحياة. تحتوي الخلية على نواة. تنتج الميتوكوندريا الطاقة."
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 32


@pytest.fixture(autouse=True)
def fresh_db(tmp_path, monkeypatch):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.db"))


@pytest.fixture
def client():
    return TestClient(app)


def register(client, email="a@example.com", password="password123"):
    r = client.post("/auth/register", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
def auth(client):
    data = register(client)
    return {"Authorization": f"Bearer {data['token']}"}, data


# ---------- عام ----------
def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


# ---------- الحسابات ----------
def test_register_and_me(client):
    data = register(client)
    assert data["plan"] == "free" and data["used"] == 0 and data["limit"] == security.PLAN_LIMITS["free"]
    me = client.get("/me", headers={"Authorization": f"Bearer {data['token']}"})
    assert me.status_code == 200 and me.json()["email"] == "a@example.com"


def test_register_email_normalized_and_unique(client):
    register(client, "User@Example.com")
    r = client.post("/auth/register", json={"email": "user@example.COM", "password": "password123"})
    assert r.status_code == 409


@pytest.mark.parametrize("email", ["", "plain", "a@b", "a b@c.com"])
def test_register_invalid_email(client, email):
    assert client.post("/auth/register", json={"email": email, "password": "password123"}).status_code == 422


def test_password_length_boundary(client):
    assert client.post("/auth/register", json={"email": "x@e.com", "password": "1234567"}).status_code == 422
    assert client.post("/auth/register", json={"email": "x@e.com", "password": "12345678"}).status_code == 200


def test_login_ok_and_wrong_password(client):
    register(client)
    ok = client.post("/auth/login", json={"email": "A@example.com", "password": "password123"})
    assert ok.status_code == 200 and ok.json()["token"]
    bad = client.post("/auth/login", json={"email": "a@example.com", "password": "wrong-password"})
    assert bad.status_code == 401
    unknown = client.post("/auth/login", json={"email": "nobody@example.com", "password": "password123"})
    assert unknown.status_code == 401
    assert bad.json()["detail"] == unknown.json()["detail"]  # لا نكشف وجود الحساب


def test_sql_injection_in_email_is_harmless(client):
    r = client.post("/auth/login", json={"email": "' OR 1=1 --", "password": "x" * 10})
    assert r.status_code == 401


def test_endpoints_require_token(client):
    assert client.get("/me").status_code == 401
    assert client.post("/summarize/text", json={"text": SAMPLE}).status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer garbage"}).status_code == 401


def test_password_not_stored_plain(client):
    import db

    register(client)
    assert "password123" not in db.get_user_by_email("a@example.com")["password_hash"]


# ---------- التلخيص ----------
def test_summarize_text(client, auth):
    headers, _ = auth
    r = client.post("/summarize/text", json={"text": SAMPLE, "language": "ar"}, headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert body["summary"] and body["key_points"] and body["source_chars"] == len(SAMPLE)
    assert client.get("/me", headers=headers).json()["used"] == 1


def test_empty_text_rejected(client, auth):
    assert client.post("/summarize/text", json={"text": ""}, headers=auth[0]).status_code == 422


def test_txt_file(client, auth):
    r = client.post(
        "/summarize/file",
        files={"file": ("a.txt", SAMPLE.encode("utf-8"), "text/plain")},
        headers=auth[0],
    )
    assert r.status_code == 200


def test_docx_file(client, auth):
    from docx import Document

    buf = io.BytesIO()
    d = Document()
    d.add_paragraph(SAMPLE)
    d.save(buf)
    r = client.post(
        "/summarize/file",
        files={"file": ("a.docx", buf.getvalue(), "application/octet-stream")},
        headers=auth[0],
    )
    assert r.status_code == 200


def test_pdf_file(client, auth):
    from reportlab.pdfgen import canvas

    buf = io.BytesIO()
    c = canvas.Canvas(buf)
    c.drawString(72, 750, "Cells are the basic unit of life. Mitochondria produce energy.")
    c.save()
    r = client.post(
        "/summarize/file",
        files={"file": ("a.pdf", buf.getvalue(), "application/pdf")},
        headers=auth[0],
    )
    assert r.status_code == 200, r.text


def test_unsupported_and_corrupt_files_do_not_consume_quota(client, auth):
    headers, _ = auth
    assert client.post("/summarize/file", files={"file": ("a.xyz", b"123", "x/y")}, headers=headers).status_code == 415
    assert client.post("/summarize/file", files={"file": ("a.pdf", b"not a pdf", "application/pdf")}, headers=headers).status_code == 400
    assert client.post("/summarize/file", files={"file": ("a.txt", b"", "text/plain")}, headers=headers).status_code == 400
    assert client.get("/me", headers=headers).json()["used"] == 0


# ---------- الحصص ----------
def test_free_quota_boundary_and_402(client, auth):
    headers, _ = auth
    limit = security.PLAN_LIMITS["free"]
    for _ in range(limit):
        assert client.post("/summarize/text", json={"text": SAMPLE}, headers=headers).status_code == 200
    r = client.post("/summarize/text", json={"text": SAMPLE}, headers=headers)
    assert r.status_code == 402 and "اشترك" in r.json()["detail"]
    # الحصة تُفحص قبل كل المسارات
    assert client.post("/summarize/audio", files={"file": ("a.mp3", b"1", "audio/mpeg")}, headers=headers).status_code == 402


def test_quota_is_per_user(client, auth):
    headers, _ = auth
    for _ in range(security.PLAN_LIMITS["free"]):
        client.post("/summarize/text", json={"text": SAMPLE}, headers=headers)
    other = register(client, "b@example.com")
    r = client.post("/summarize/text", json={"text": SAMPLE}, headers={"Authorization": f"Bearer {other['token']}"})
    assert r.status_code == 200


# ---------- الصوت ----------
def test_audio_ok_returns_transcript(client, auth):
    r = client.post("/summarize/audio", files={"file": ("lec.m4a", b"fake-audio", "audio/mp4")}, headers=auth[0])
    assert r.status_code == 200
    assert r.json()["transcript"]


def test_audio_rejects_wrong_type_empty_and_big(client, auth, monkeypatch):
    headers, _ = auth
    assert client.post("/summarize/audio", files={"file": ("a.txt", b"x", "text/plain")}, headers=headers).status_code == 415
    assert client.post("/summarize/audio", files={"file": ("a.mp3", b"", "audio/mpeg")}, headers=headers).status_code == 400
    monkeypatch.setattr(media, "MAX_AUDIO_MB", 0)
    assert client.post("/summarize/audio", files={"file": ("a.mp3", b"x", "audio/mpeg")}, headers=headers).status_code == 413
    assert client.get("/me", headers=headers).json()["used"] == 0


# ---------- الصور ----------
def test_images_ok(client, auth):
    r = client.post(
        "/summarize/image",
        files=[("files", ("p1.png", PNG, "image/png")), ("files", ("p2.jpg", PNG, "image/jpeg"))],
        headers=auth[0],
    )
    assert r.status_code == 200 and r.json()["transcript"]


def test_images_rejects_bad_type_and_too_many(client, auth):
    headers, _ = auth
    bad = client.post("/summarize/image", files=[("files", ("a.bmp", PNG, "image/bmp"))], headers=headers)
    assert bad.status_code == 415
    many = [("files", (f"p{i}.png", PNG, "image/png")) for i in range(media.MAX_IMAGES + 1)]
    assert client.post("/summarize/image", files=many, headers=headers).status_code == 413


# ---------- الاشتراكات ----------
def _event(etype, user_id):
    return {"event": {"type": etype, "app_user_id": str(user_id)}}


def test_webhook_requires_auth(client, auth):
    _, data = auth
    assert client.post("/webhooks/revenuecat", json=_event("INITIAL_PURCHASE", data["user_id"])).status_code == 401
    r = client.post("/webhooks/revenuecat", json=_event("INITIAL_PURCHASE", data["user_id"]), headers={"Authorization": "wrong"})
    assert r.status_code == 401


def test_webhook_upgrade_cancel_expire(client, auth):
    headers, data = auth
    rc = {"Authorization": "rc-secret"}

    def plan():
        return client.get("/me", headers=headers).json()

    client.post("/webhooks/revenuecat", json=_event("INITIAL_PURCHASE", data["user_id"]), headers=rc)
    assert plan()["plan"] == "pro" and plan()["limit"] == security.PLAN_LIMITS["pro"]
    client.post("/webhooks/revenuecat", json=_event("CANCELLATION", data["user_id"]), headers=rc)
    assert plan()["plan"] == "pro"  # يبقى حتى انتهاء المدة المدفوعة
    client.post("/webhooks/revenuecat", json=_event("EXPIRATION", data["user_id"]), headers=rc)
    assert plan()["plan"] == "free"


def test_webhook_unknown_user_ignored(client):
    r = client.post("/webhooks/revenuecat", json=_event("INITIAL_PURCHASE", "$RCAnonymousID:abc"), headers={"Authorization": "rc-secret"})
    assert r.status_code == 200 and r.json().get("ignored")


def test_upgrade_lifts_quota(client, auth):
    headers, data = auth
    for _ in range(security.PLAN_LIMITS["free"]):
        client.post("/summarize/text", json={"text": SAMPLE}, headers=headers)
    assert client.post("/summarize/text", json={"text": SAMPLE}, headers=headers).status_code == 402
    client.post("/webhooks/revenuecat", json=_event("RENEWAL", data["user_id"]), headers={"Authorization": "rc-secret"})
    assert client.post("/summarize/text", json={"text": SAMPLE}, headers=headers).status_code == 200


# ---------- منطق التلخيص ----------
def test_split_text():
    text = "\n\n".join(["فقرة " * 50] * 40)
    chunks = split_text(text, 1000)
    assert len(chunks) > 1 and all(len(c) <= 1000 for c in chunks)
    assert split_text("قصير", 1000) == ["قصير"]


def test_parse_json_reply():
    raw = '```json\n{"title":"ت","summary":"م","key_points":["أ"],"terms":[{"term":"ك","definition":"ع"}]}\n```'
    out = parse_json_reply(raw)
    assert out["title"] == "ت" and out["terms"][0]["term"] == "ك"


# ---------- المراجعة: بطاقات واختبارات ----------
STUDY_BODY = {
    "summary": "الخلية هي الوحدة الأساسية للحياة. تنتج الميتوكوندريا الطاقة. تحتوي الخلية على نواة تحمل المادة الوراثية.",
    "key_points": ["الخلية وحدة الحياة", "الميتوكوندريا مصدر الطاقة"],
    "terms": [{"term": "النواة", "definition": "تحمل المادة الوراثية"}],
}


def test_study_requires_token(client):
    assert client.post("/study/generate", json=STUDY_BODY).status_code == 401


def test_study_generate_ok_and_consumes_one_use(client, auth):
    headers, _ = auth
    r = client.post("/study/generate", json=STUDY_BODY, headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["flashcards"] and body["quiz"]
    for q in body["quiz"]:
        assert len(q["options"]) == 4 and 0 <= q["answer_index"] < 4
    assert client.get("/me", headers=headers).json()["used"] == 1


@pytest.mark.parametrize(
    "patch",
    [{"summary": ""}, {"cards": 0}, {"cards": study.MAX_CARDS + 1}, {"questions": 0}, {"questions": study.MAX_QUESTIONS + 1}],
)
def test_study_input_boundaries(client, auth, patch):
    r = client.post("/study/generate", json={**STUDY_BODY, **patch}, headers=auth[0])
    assert r.status_code == 422
    assert client.get("/me", headers=auth[0]).json()["used"] == 0


def test_study_respects_quota(client, auth):
    headers, _ = auth
    for _ in range(security.PLAN_LIMITS["free"]):
        assert client.post("/study/generate", json=STUDY_BODY, headers=headers).status_code == 200
    assert client.post("/study/generate", json=STUDY_BODY, headers=headers).status_code == 402


def test_study_upstream_failure_is_502_and_free(client, auth, monkeypatch):
    def boom(*a, **k):
        raise SummarizerError("فشل")

    monkeypatch.setattr(study, "generate_study", boom)
    headers, _ = auth
    assert client.post("/study/generate", json=STUDY_BODY, headers=headers).status_code == 502
    assert client.get("/me", headers=headers).json()["used"] == 0


def _q(**over):
    base = {"question": "ما هي؟", "options": ["أ", "ب", "ج", "د"], "answer_index": 1, "explanation": "لأن"}
    base.update(over)
    return base


def test_validate_study_drops_bad_items_keeps_good():
    data = {
        "flashcards": [{"front": "س", "back": "ج"}, {"front": "", "back": "x"}, "junk", {"front": "فقط"}],
        "quiz": [
            _q(),
            _q(options=["أ", "ب", "ج"]),  # ثلاثة خيارات
            _q(options=["أ", "أ", "ج", "د"]),  # مكرر
            _q(answer_index=4),  # خارج النطاق
            _q(answer_index=-1),
            _q(answer_index=True),  # bool ليس رقماً صالحاً
            _q(answer_index="1"),
            _q(question="  "),
        ],
    }
    out = study.validate_study(data, 10, 10)
    assert out["flashcards"] == [{"front": "س", "back": "ج"}]
    assert len(out["quiz"]) == 1 and out["quiz"][0]["answer_index"] == 1


def test_validate_study_truncates_and_fails_when_empty():
    cards = [{"front": f"س{i}", "back": "ج"} for i in range(20)]
    assert len(study.validate_study({"flashcards": cards}, 5, 5)["flashcards"]) == 5
    with pytest.raises(SummarizerError):
        study.validate_study({"flashcards": [], "quiz": [_q(answer_index=9)]}, 5, 5)
    with pytest.raises(SummarizerError):
        study.validate_study({}, 5, 5)


def test_parse_json_object_rejects_non_object():
    from summarizer import parse_json_object

    with pytest.raises(SummarizerError):
        parse_json_object("[1, 2, 3]")
    with pytest.raises(SummarizerError):
        parse_json_object("لا يوجد json")


# ---------- حالات حدّية اكتُشفت أثناء المراجعة ----------
def test_whitespace_only_text_is_422_and_free(client, auth):
    r = client.post("/summarize/text", json={"text": "   \n\t  "}, headers=auth[0])
    assert r.status_code == 422
    assert client.get("/me", headers=auth[0]).json()["used"] == 0


def test_whitespace_only_study_summary_is_422_and_free(client, auth):
    r = client.post("/study/generate", json={"summary": "   \n "}, headers=auth[0])
    assert r.status_code == 422
    assert client.get("/me", headers=auth[0]).json()["used"] == 0


def test_parse_json_reply_tolerates_unexpected_types():
    out = parse_json_reply(
        '{"title": null, "summary": "م", "key_points": "ليست قائمة", "terms": "أيضاً"}'
    )
    assert out["title"] == "ملخص جديد"
    assert out["summary"] == "م"
    assert out["key_points"] == []
    assert out["terms"] == []


def test_validate_study_rejects_string_options():
    out = study.validate_study(
        {"quiz": [_q(options="ابجد")], "flashcards": [{"front": "س", "back": "ج"}]}, 5, 5
    )
    assert out["quiz"] == [] and len(out["flashcards"]) == 1


def test_audio_and_image_upstream_errors_are_502_and_free(client, auth, monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("upstream down")

    monkeypatch.setattr(media, "transcribe", boom)
    monkeypatch.setattr(media, "ocr_images", boom)
    headers, _ = auth
    assert (
        client.post("/summarize/audio", files={"file": ("a.mp3", b"x", "audio/mpeg")}, headers=headers).status_code
        == 502
    )
    assert (
        client.post("/summarize/image", files=[("files", ("p.png", PNG, "image/png"))], headers=headers).status_code
        == 502
    )
    assert client.get("/me", headers=headers).json()["used"] == 0


# ---------- ميزات v0.3 ----------
def test_oauth_login_google_mock(client):
    token = jwt.encode({"email": "oauth@example.com", "sub": "google-sub-1"}, "x", algorithm="HS256")
    r = client.post("/auth/oauth", json={"provider": "google", "id_token": token})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["email"] == "oauth@example.com"
    assert body["token"]


def test_password_reset_flow(client):
    register(client, "reset@example.com", "oldpassword")
    req = client.post("/auth/forgot-password", json={"email": "reset@example.com"})
    assert req.status_code == 200
    token = req.json()["dev_token"]
    done = client.post("/auth/reset-password", json={"token": token, "new_password": "newpassword123"})
    assert done.status_code == 200, done.text
    old = client.post("/auth/login", json={"email": "reset@example.com", "password": "oldpassword"})
    new = client.post("/auth/login", json={"email": "reset@example.com", "password": "newpassword123"})
    assert old.status_code == 401
    assert new.status_code == 200


def test_delete_account(client):
    data = register(client, "del@example.com", "password123")
    headers = {'Authorization': 'Bearer ' + data['token']}
    r = client.delete("/me", headers=headers)
    assert r.status_code == 200
    assert client.get("/me", headers=headers).status_code == 401


def test_ask_endpoint(client, auth):
    headers, _ = auth
    r = client.post(
        "/ask",
        json={
            "summary": "الخلية هي الوحدة الأساسية للحياة وتحتوي على نواة.",
            "question": "ما الوحدة الأساسية للحياة؟",
            "language": "ar",
        },
        headers=headers,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["answer"]
    assert "grounded" in body


def test_library_crud_and_sync(client, auth):
    headers, _ = auth
    item = {
        "id": "s-1",
        "title": "ملخص الأحياء",
        "summary": "الخلية هي الوحدة الأساسية للحياة.",
        "key_points": ["الخلية وحدة الحياة"],
        "terms": [{"term": "النواة", "definition": "تحمل المادة الوراثية"}],
        "language": "ar",
        "created_at": 100,
        "updated_at": 100,
    }
    put = client.put("/library", json=item, headers=headers)
    assert put.status_code == 200, put.text
    assert put.json()["id"] == "s-1"

    listing = client.get("/library", headers=headers)
    assert listing.status_code == 200
    assert len(listing.json()) == 1

    synced = client.post(
        "/library/sync",
        json={"items": [{**item, "summary": "نسخة أحدث", "updated_at": 200}]},
        headers=headers,
    )
    assert synced.status_code == 200
    assert synced.json()[0]["summary"] == "نسخة أحدث"

    deleted = client.delete("/library/s-1", headers=headers)
    assert deleted.status_code == 200
    assert client.get("/library", headers=headers).json() == []
