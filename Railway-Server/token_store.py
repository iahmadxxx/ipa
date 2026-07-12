"""
token_store.py
Persistent runtime token overrides stored in the same SQLite database/Volume.
Environment variables remain the initial fallback, so old Railway settings keep working.
"""

import os
import sqlite3

DB_PATH = os.environ.get("GYM_DB_PATH", "gym_data.db")


def _conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS app_tokens ("
        "  name TEXT PRIMARY KEY,"
        "  value TEXT NOT NULL,"
        "  updated_at TEXT DEFAULT CURRENT_TIMESTAMP"
        ")"
    )
    return conn


def get_token(name, env_name=None):
    """Database override first, then the existing Railway environment variable."""
    try:
        conn = _conn()
        row = conn.execute(
            "SELECT value FROM app_tokens WHERE name = ?", (str(name),)
        ).fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except sqlite3.Error:
        pass
    return os.environ.get(env_name) if env_name else None


def save_token(name, value):
    value = str(value or "").strip()
    if not value:
        raise ValueError("قيمة التوكن فارغة")
    conn = _conn()
    conn.execute(
        "INSERT INTO app_tokens (name, value, updated_at) "
        "VALUES (?, ?, CURRENT_TIMESTAMP) "
        "ON CONFLICT(name) DO UPDATE SET value = excluded.value, "
        "updated_at = CURRENT_TIMESTAMP",
        (str(name), value),
    )
    conn.commit()
    conn.close()


def token_updated_at(name="google_refresh_token"):
    try:
        conn = _conn()
        row = conn.execute(
            "SELECT updated_at FROM app_tokens WHERE name = ?", (str(name),)
        ).fetchone()
        conn.close()
        return row[0] if row else None
    except sqlite3.Error:
        return None


def get_refresh_token():
    return get_token("google_refresh_token", "GOOGLE_REFRESH_TOKEN")


def save_refresh_token(token):
    save_token("google_refresh_token", token)


def get_gemini_api_key():
    return get_token("gemini_api_key", "GEMINI_API_KEY")


def save_gemini_api_key(token):
    save_token("gemini_api_key", token)
