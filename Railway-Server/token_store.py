"""
token_store.py
تخزين واسترجاع Google refresh token بقاعدة البيانات بدل متغير البيئة الثابت.
الأولوية: قاعدة البيانات → متغير البيئة (كقيمة أولية/احتياطية).
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


def get_refresh_token():
    """يرجع التوكن من قاعدة البيانات، وإلا من متغير البيئة."""
    try:
        conn = _conn()
        row = conn.execute(
            "SELECT value FROM app_tokens WHERE name = 'google_refresh_token'"
        ).fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except sqlite3.Error:
        pass
    return os.environ.get("GOOGLE_REFRESH_TOKEN")


def save_refresh_token(token):
    """يحفظ توكن جديد (يستبدل القديم)."""
    conn = _conn()
    conn.execute(
        "INSERT INTO app_tokens (name, value, updated_at) "
        "VALUES ('google_refresh_token', ?, CURRENT_TIMESTAMP) "
        "ON CONFLICT(name) DO UPDATE SET value = excluded.value, "
        "updated_at = CURRENT_TIMESTAMP",
        (token,),
    )
    conn.commit()
    conn.close()


def token_updated_at():
    """يرجع آخر وقت تحديث للتوكن (نص) أو None."""
    try:
        conn = _conn()
        row = conn.execute(
            "SELECT updated_at FROM app_tokens WHERE name = 'google_refresh_token'"
        ).fetchone()
        conn.close()
        return row[0] if row else None
    except sqlite3.Error:
        return None
