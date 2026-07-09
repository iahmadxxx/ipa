"""خدمة Cron أسبوعية ترسل تقرير الأداء الكامل."""
try:
    import env_config  # noqa: F401
except ImportError:
    pass

import os
import requests

import gym_tracker
from google_health_client import get_today_summary
from performance_intelligence import weekly_report

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"


def main():
    gym_tracker.init_db()
    try:
        today = get_today_summary()
    except Exception:
        today = None
    text = weekly_report(today)
    requests.post(
        f"{TELEGRAM_API}/sendMessage",
        data={"chat_id": CHAT_ID, "text": text},
        timeout=20,
    ).raise_for_status()


if __name__ == "__main__":
    main()
