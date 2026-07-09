"""
daily_summary.py — نسخة Railway
يُشغَّل كخدمة Cron مجدولة على Railway (مرة يوميًا) لإرسال الملخص الصباحي.
Railway يمرر متغيرات البيئة مباشرة، فما نحتاج env_config.
"""

try:
    import env_config  # noqa: F401  # محلي فقط
except ImportError:
    pass

import os
import requests
from datetime import datetime, timezone, timedelta

from google_health_client import get_today_summary, GoogleHealthError
from analyzer import format_today_message
import gym_tracker
from performance_intelligence import format_readiness, weekly_report

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"


def send_message(text):
    requests.post(f"{TELEGRAM_API}/sendMessage", data={
        "chat_id": CHAT_ID, "text": text,
    }, timeout=15)


def main():
    try:
        gym_tracker.init_db()
        data = get_today_summary()
        message = format_today_message(data) + "\n\n" + format_readiness(data)
        # كل جمعة صباحًا يضاف التقرير الأسبوعي تلقائيًا لنفس الرسالة.
        local_now = datetime.now(timezone.utc) + timedelta(hours=3)
        if local_now.weekday() == 4:
            message += "\n\n" + weekly_report(data)
    except GoogleHealthError as e:
        message = f"⚠️ تعذر جلب ملخص اليوم:\n{e}"
    except Exception as e:
        message = f"⚠️ خطأ غير متوقع بالملخص اليومي:\n{e}"

    send_message(message)


if __name__ == "__main__":
    main()
