"""قاعدة بيانات SQLite للتطبيق (مستخدمون، استخدام، مكتبة، استعادة كلمة المرور)."""
import os
import json
import sqlite3
import threading
import time
from contextlib import contextmanager
from typing import List, Optional

_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT,
    plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro')),
    oauth_provider TEXT,
    oauth_sub TEXT,
    created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth ON users(oauth_provider, oauth_sub);
CREATE TABLE IF NOT EXISTS usage (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    month TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, month)
);
CREATE TABLE IF NOT EXISTS summaries (
    id TEXT NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    key_points_json TEXT NOT NULL DEFAULT '[]',
    terms_json TEXT NOT NULL DEFAULT '[]',
    language TEXT NOT NULL DEFAULT 'ar',
    transcript TEXT,
    study_json TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_summaries_user_updated ON summaries(user_id, updated_at DESC);
CREATE TABLE IF NOT EXISTS password_resets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at INTEGER NOT NULL,
    used_at INTEGER,
    created_at INTEGER NOT NULL
);
"""

_ready: set = set()
_lock = threading.Lock()


def db_path() -> str:
    return os.getenv("DB_PATH", "mulakhis.db")


@contextmanager
def conn():
    path = db_path()
    c = sqlite3.connect(path, timeout=10)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys = ON")
    with _lock:
        if path not in _ready:
            c.executescript(_SCHEMA)
            _ready.add(path)
    try:
        yield c
        c.commit()
    finally:
        c.close()


def current_month() -> str:
    return time.strftime("%Y-%m", time.gmtime())


def create_user(email: str, password_hash: str) -> int:
    try:
        with conn() as c:
            cur = c.execute(
                "INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
                (email, password_hash, int(time.time())),
            )
            return int(cur.lastrowid)
    except sqlite3.IntegrityError as e:
        raise ValueError("email exists") from e


def get_user_by_email(email: str) -> Optional[sqlite3.Row]:
    with conn() as c:
        return c.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()


def get_user(user_id: int) -> Optional[sqlite3.Row]:
    with conn() as c:
        return c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def get_or_create_oauth_user(provider: str, sub: str, email: str) -> int:
    with conn() as c:
        row = c.execute(
            "SELECT id FROM users WHERE oauth_provider = ? AND oauth_sub = ?",
            (provider, sub),
        ).fetchone()
        if row:
            return int(row["id"])

        row = c.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if row:
            c.execute(
                "UPDATE users SET oauth_provider = ?, oauth_sub = ? WHERE id = ?",
                (provider, sub, int(row["id"])),
            )
            return int(row["id"])

        cur = c.execute(
            "INSERT INTO users (email, password_hash, oauth_provider, oauth_sub, created_at) "
            "VALUES (?, NULL, ?, ?, ?)",
            (email, provider, sub, int(time.time())),
        )
        return int(cur.lastrowid)


def set_plan(user_id: int, plan: str) -> bool:
    with conn() as c:
        cur = c.execute("UPDATE users SET plan = ? WHERE id = ?", (plan, user_id))
        return cur.rowcount > 0


def usage_count(user_id: int, month: Optional[str] = None) -> int:
    with conn() as c:
        row = c.execute(
            "SELECT count FROM usage WHERE user_id = ? AND month = ?",
            (user_id, month or current_month()),
        ).fetchone()
        return int(row["count"]) if row else 0


def add_usage(user_id: int, month: Optional[str] = None) -> None:
    with conn() as c:
        c.execute(
            "INSERT INTO usage (user_id, month, count) VALUES (?, ?, 1) "
            "ON CONFLICT(user_id, month) DO UPDATE SET count = count + 1",
            (user_id, month or current_month()),
        )


def _to_json(value) -> str:
    return json.dumps(value, ensure_ascii=False)


def _summary_row(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "title": row["title"],
        "summary": row["summary"],
        "key_points": json.loads(row["key_points_json"] or "[]"),
        "terms": json.loads(row["terms_json"] or "[]"),
        "language": row["language"] or "ar",
        "transcript": row["transcript"],
        "study": json.loads(row["study_json"]) if row["study_json"] else None,
        "created_at": int(row["created_at"]),
        "updated_at": int(row["updated_at"]),
    }


def upsert_summary(user_id: int, item: dict) -> dict:
    now = int(time.time())
    sid = str(item.get("id") or "")
    if not sid:
        raise ValueError("summary id required")
    created = int(item.get("created_at") or now)
    updated = int(item.get("updated_at") or now)
    with conn() as c:
        c.execute(
            """
            INSERT INTO summaries
                (id, user_id, title, summary, key_points_json, terms_json, language, transcript, study_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id, user_id) DO UPDATE SET
                title = excluded.title,
                summary = excluded.summary,
                key_points_json = excluded.key_points_json,
                terms_json = excluded.terms_json,
                language = excluded.language,
                transcript = excluded.transcript,
                study_json = excluded.study_json,
                updated_at = excluded.updated_at
            """,
            (
                sid,
                user_id,
                str(item.get("title") or "\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f"),
                str(item.get("summary") or ""),
                _to_json(item.get("key_points") or []),
                _to_json(item.get("terms") or []),
                str(item.get("language") or "ar"),
                item.get("transcript"),
                _to_json(item.get("study")) if item.get("study") is not None else None,
                created,
                updated,
            ),
        )
        row = c.execute(
            "SELECT * FROM summaries WHERE user_id = ? AND id = ?",
            (user_id, sid),
        ).fetchone()
        return _summary_row(row)


def list_summaries(user_id: int) -> List[dict]:
    with conn() as c:
        rows = c.execute(
            "SELECT * FROM summaries WHERE user_id = ? ORDER BY updated_at DESC",
            (user_id,),
        ).fetchall()
        return [_summary_row(r) for r in rows]


def get_summary(user_id: int, summary_id: str) -> Optional[dict]:
    with conn() as c:
        row = c.execute(
            "SELECT * FROM summaries WHERE user_id = ? AND id = ?",
            (user_id, summary_id),
        ).fetchone()
        return _summary_row(row) if row else None


def delete_summary(user_id: int, summary_id: str) -> bool:
    with conn() as c:
        cur = c.execute(
            "DELETE FROM summaries WHERE user_id = ? AND id = ?",
            (user_id, summary_id),
        )
        return cur.rowcount > 0


def create_password_reset(user_id: int, token_hash: str, expires_at: int) -> int:
    with conn() as c:
        c.execute("DELETE FROM password_resets WHERE user_id = ? AND used_at IS NULL", (user_id,))
        cur = c.execute(
            "INSERT INTO password_resets (user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?)",
            (user_id, token_hash, expires_at, int(time.time())),
        )
        return int(cur.lastrowid)


def get_password_reset(token_hash: str) -> Optional[sqlite3.Row]:
    with conn() as c:
        return c.execute(
            "SELECT * FROM password_resets WHERE token_hash = ?",
            (token_hash,),
        ).fetchone()


def mark_password_reset_used(reset_id: int) -> None:
    with conn() as c:
        c.execute(
            "UPDATE password_resets SET used_at = ? WHERE id = ?",
            (int(time.time()), reset_id),
        )


def set_password(user_id: int, password_hash: str) -> bool:
    with conn() as c:
        cur = c.execute(
            "UPDATE users SET password_hash = ? WHERE id = ?",
            (password_hash, user_id),
        )
        return cur.rowcount > 0


def delete_user(user_id: int) -> bool:
    with conn() as c:
        cur = c.execute("DELETE FROM users WHERE id = ?", (user_id,))
        return cur.rowcount > 0
