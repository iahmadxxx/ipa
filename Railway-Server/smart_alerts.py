"""تنبيهات ذكية شخصية: نوم، نبض راحة، ونشاط أقل من المعتاد."""
try:
    import env_config  # noqa: F401
except ImportError:
    pass

import os
from datetime import datetime, timezone, timedelta
import requests

import gym_tracker
from google_health_client import get_today_summary, get_week_summary
from performance_intelligence import calculate_readiness

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"
LOCAL_OFFSET = 3


def send_message(text):
    requests.post(
        f"{TELEGRAM_API}/sendMessage",
        data={"chat_id": CHAT_ID, "text": text},
        timeout=15,
    ).raise_for_status()


def main():
    gym_tracker.init_db()
    now = datetime.now(timezone.utc) + timedelta(hours=LOCAL_OFFSET)
    if now.hour < 9 or now.hour >= 23:
        return

    try:
        today = get_today_summary()
        week = get_week_summary()
        readiness = calculate_readiness(today)
    except Exception:
        return

    alerts = []
    sleep = readiness.get("sleep_minutes")
    if sleep is not None and sleep < 360 and not gym_tracker.notification_sent("low_sleep"):
        alerts.append(f"😴 نومك كان {sleep//60}س {sleep%60}د فقط؛ خفف الشدة لو حسيت تعب.")
        gym_tracker.mark_notification_sent("low_sleep")

    baseline = readiness.get("baseline") or {}
    rhr = today.get("heart_rate")
    base_rhr = baseline.get("resting_hr")
    if rhr and base_rhr and baseline.get("resting_hr_count", 0) >= 3:
        if rhr >= base_rhr + 7 and not gym_tracker.notification_sent("high_rhr"):
            alerts.append(f"❤️ نبض الراحة أعلى من خطك الطبيعي بحوالي {rhr-base_rhr:.0f} نبضة.")
            gym_tracker.mark_notification_sent("high_rhr")

    # نشاط شخصي: قارن تقدم اليوم بمتوسط آخر الأيام المكتملة
    steps = today.get("steps") or 0
    previous = [d.get("steps") for d in week[:-1] if d.get("steps")]
    if previous and now.hour >= 16:
        avg_daily = sum(previous) / len(previous)
        elapsed = min(1.0, max(0.1, (now.hour - 8) / 15))
        expected_now = avg_daily * elapsed
        if steps < expected_now * 0.55 and not gym_tracker.notification_sent("low_activity"):
            alerts.append(
                f"🚶 خطواتك {steps:,} فقط، وأنت عادة تكون قريب من {int(expected_now):,} بهذا الوقت. مشية 10 دقائق تفرق."
            )
            gym_tracker.mark_notification_sent("low_activity")

    if readiness["score"] < 50 and not gym_tracker.notification_sent("low_readiness"):
        alerts.append(f"⚡ جاهزيتك اليوم {readiness['score']}/100؛ الأفضل تخفيف الحمل أو أخذ راحة.")
        gym_tracker.mark_notification_sent("low_readiness")

    if alerts:
        send_message("🧠 تنبيه ذكي مبني على بياناتك:\n\n" + "\n\n".join(alerts))


if __name__ == "__main__":
    main()
