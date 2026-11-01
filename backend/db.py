"""قاعدة بيانات SQLite بسيطة: المستخدمون وعدّاد الاستخدام الشهري.

للإنتاج بعدد مستخدمين كبير انتقل إلى PostgreSQL (البنية نفسها).
"""
import os
import sqlite3
import threading
import time
from contextlib import contextmanager
from typing import Optional

_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro')),
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS usage (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    month TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, month)
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
