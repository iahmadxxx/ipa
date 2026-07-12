"""
webhook_app.py — النسخة الكاملة
- أزرار تواريخ لكل أمر إحصائي (today/sleep/heart/activity)
- AI محادثة متعددة الأدوار مع ذاكرة (multi-turn)
- تسجيل كل الأوامر في Telegram menu
"""

try:
    import env_config  # noqa: F401
except ImportError:
    pass

import os
import re
import json
import datetime
import hashlib
import base64
import hmac
import time
from urllib.parse import parse_qsl

import requests
from flask import Flask, request, jsonify, Response

from google_health_client import (
    get_today_summary, get_week_summary, get_sleep, get_resting_heart_rate,
    get_current_heart_rate, get_summary_by_date, get_week_summary_for, GoogleHealthError,
    TokenExpiredError, get_access_token, get_steps, get_calories, get_paired_devices,
    list_exercises, create_exercise_session,
)
import token_store
from analyzer import (
    format_today_message, format_week_message, format_sleep_message,
    format_heart_message, format_activity_message,
)
from ai_coach import analyze_week, ask_coach, transcribe_audio, analyze_images_json, generate_structured_json, AICoachError
import gym_tracker
import wellness_tracker
import activity_tracker
from performance_intelligence import (
    format_readiness, today_plan, progress_report, format_muscle_balance,
    format_next_suggestions, weekly_report, recommend_next_weight,
    detect_pr, coach_context,
)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 28 * 1024 * 1024
gym_tracker.init_db()
wellness_tracker.init_db()
activity_tracker.init_db()

_IOS_CACHE = {}

def _cache_get(key, ttl_seconds):
    item = _IOS_CACHE.get(key)
    if not item:
        return None
    if time.monotonic() - item["time"] > ttl_seconds:
        _IOS_CACHE.pop(key, None)
        return None
    return item["value"]

def _cache_set(key, value):
    _IOS_CACHE[key] = {"time": time.monotonic(), "value": value}
    return value

def _invalidate_ios_cache(prefixes=None):
    if not prefixes:
        _IOS_CACHE.clear()
        return
    prefixes = tuple(prefixes)
    for key in list(_IOS_CACHE):
        if str(key).startswith(prefixes):
            _IOS_CACHE.pop(key, None)

def _local_today_iso():
    return (datetime.datetime.utcnow() + datetime.timedelta(hours=3)).date().isoformat()


def _health_archive_ttl(kind, date_str):
    is_today = date_str == _local_today_iso()
    if kind == "heart":
        return 30 if is_today else 3600
    if kind == "activity":
        return 60 if is_today else 3600
    if kind == "sleep":
        return 300 if is_today else 21600
    if kind == "readiness":
        return 120 if is_today else 21600
    return 120 if is_today else 3600


def _health_archive_cached(kind, date_str, loader, force=False):
    # v3 invalidates old sleep payloads produced by previous timezone logic.
    cache_version = "v3" if kind == "sleep" else "v1"
    key = f"health:{cache_version}:{kind}:{date_str}"
    payload = None if force else _cache_get(key, _health_archive_ttl(kind, date_str))
    cache_hit = payload is not None

    if payload is None:
        started = time.monotonic()
        payload = loader()
        payload["_server_ms"] = int((time.monotonic() - started) * 1000)
        payload["_updated_at"] = datetime.datetime.utcnow().isoformat()
        _cache_set(key, payload)

    return payload, cache_hit


def _payload_sleep(date_str):
    sleep = get_sleep(date_str)
    return {"ok": True, "date": date_str, "sleep": _sleep_details_ios(sleep)}


def _payload_heart(date_str):
    resting = get_resting_heart_rate(date_str)
    current_bpm = None
    current_time = None

    if date_str == _local_today_iso():
        current = get_current_heart_rate()
        if current:
            current_bpm, current_dt = current
            current_time = current_dt.isoformat() if current_dt else None

    return {
        "ok": True,
        "date": date_str,
        "heart": {
            "current_bpm": current_bpm,
            "resting_bpm": resting,
            "last_reading_at": current_time,
        },
    }


def _payload_activity(date_str):
    return {
        "ok": True,
        "date": date_str,
        "activity": {
            "steps": get_steps(date_str),
            "calories": get_calories(date_str),
        },
    }


def _payload_readiness(date_str):
    summary = get_summary_by_date(date_str)
    return {
        "ok": True,
        "date": date_str,
        "readiness": format_readiness(summary),
        "today_plan": today_plan(summary),
    }


def _payload_summary(date_str):
    return {"ok": True, "date": date_str, "dashboard": _dashboard_payload(date_str)}


def _parse_google_timestamp(value):
    if not value:
        return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    try:
        return datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except Exception:
        return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)



def _normalize_battery_level(value):
    if value is None:
        return None
    try:
        level = int(value)
        return max(0, min(100, level))
    except Exception:
        return None


def _device_contract(
    status,
    *,
    device=None,
    battery_level=None,
    battery_status=None,
    last_sync_time=None,
    message="",
    reauth_url=None,
):
    """The one and only device-status JSON contract."""
    status = status if status in {"ok", "reauth", "unavailable"} else "unavailable"
    needs_reauth = status == "reauth"
    return {
        "ok": status == "ok",
        "status": status,
        "connected": status == "ok",
        "needs_reauth": needs_reauth,
        "device": str(device) if device else None,
        "battery_level": _normalize_battery_level(battery_level),
        "battery_status": str(battery_status).upper() if battery_status else None,
        "last_sync_time": str(last_sync_time) if last_sync_time else None,
        "message": str(message or ""),
        "reauth_url": str(reauth_url) if reauth_url else None,
    }


def _heart_contract(
    status,
    *,
    bpm=None,
    measured_at=None,
    age_seconds=None,
    message="",
):
    """The one and only live-heart JSON contract."""
    status = status if status in {"ok", "no_data", "reauth", "unavailable"} else "unavailable"
    normalized_bpm = None
    try:
        normalized_bpm = int(bpm) if bpm is not None else None
    except Exception:
        normalized_bpm = None

    if status == "ok" and normalized_bpm is None:
        status = "no_data"
        message = "لا توجد قراءة نبض متاحة حتى الآن."

    normalized_age = None
    try:
        normalized_age = max(0, int(age_seconds)) if age_seconds is not None else None
    except Exception:
        normalized_age = None

    return {
        "ok": status == "ok",
        "status": status,
        "bpm": normalized_bpm,
        "measured_at": str(measured_at) if measured_at else None,
        "age_seconds": normalized_age,
        "stale": normalized_age is None or normalized_age > 120,
        "needs_reauth": status == "reauth",
        "message": str(message or ""),
    }


def _device_status_payload():
    devices = get_paired_devices()
    trackers = [
        d for d in devices
        if str(d.get("deviceType", "")).upper() != "SCALE"
    ]
    candidates = trackers or devices

    if not candidates:
        return _device_contract(
            "unavailable",
            message="لم أجد سوارًا مقترنًا في Google Health.",
        )

    device = max(
        candidates,
        key=lambda d: _parse_google_timestamp(d.get("lastSyncTime")),
    )

    return _device_contract(
        "ok",
        device=device.get("deviceVersion") or "Fitbit",
        battery_level=device.get("batteryLevel"),
        battery_status=device.get("batteryStatus"),
        last_sync_time=device.get("lastSyncTime"),
        message="تم جلب حالة السوار.",
    )


def _iso_age_seconds(value):
    if not value:
        return None
    try:
        dt = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        now = datetime.datetime.now(datetime.timezone.utc)
        return max(0, int((now - dt.astimezone(datetime.timezone.utc)).total_seconds()))
    except Exception:
        return None


def _live_heart_payload():
    current = get_current_heart_rate()
    if not current:
        cached = _cache_get("heart:last_valid", 72 * 3600)
        if cached and cached.get("bpm") and cached.get("measured_at"):
            cached = dict(cached)
            cached["age_seconds"] = _iso_age_seconds(cached.get("measured_at"))
            cached["stale"] = True
            cached["message"] = "آخر قراءة نبض محفوظة من Fitbit."
            return cached
        return _heart_contract(
            "no_data",
            message="لا توجد قراءة نبض موثقة بوقت مطابق حتى الآن.",
        )

    bpm, measured_dt = current

    # BPM and time must still belong to the same Google Health data point.
    if bpm is None or measured_dt is None:
        cached = _cache_get("heart:last_valid", 72 * 3600)
        if cached and cached.get("bpm") and cached.get("measured_at"):
            return cached
        return _heart_contract(
            "no_data",
            message="وصلت بيانات نبض غير مكتملة وتم رفض عرضها.",
        )

    measured_at = measured_dt.isoformat()
    age_seconds = _iso_age_seconds(measured_at)
    payload = _heart_contract(
        "ok",
        bpm=bpm,
        measured_at=measured_at,
        age_seconds=age_seconds,
        message="تم جلب أحدث قراءة نبض موثقة.",
    )
    _cache_set("heart:last_valid", payload)
    return payload


def _safe_device_status_payload():
    try:
        return _device_status_payload()
    except TokenExpiredError:
        return _device_contract(
            "reauth",
            message="يحتاج تجديد ربط Google Health.",
            reauth_url=_reauth_url(),
        )
    except GoogleHealthError as exc:
        text = str(exc)
        needs_reauth = (
            "403" in text
            or "PERMISSION_DENIED" in text
            or "insufficient" in text.lower()
        )
        if needs_reauth:
            return _device_contract(
                "reauth",
                message="جدد الربط مرة واحدة لتفعيل حالة السوار.",
                reauth_url=_reauth_url(),
            )
        return _device_contract(
            "unavailable",
            message="حالة السوار غير متاحة مؤقتًا.",
        )
    except Exception:
        return _device_contract(
            "unavailable",
            message="حالة السوار غير متاحة مؤقتًا.",
        )


def _safe_live_heart_payload():
    try:
        return _live_heart_payload()
    except TokenExpiredError:
        return _heart_contract(
            "reauth",
            message="يحتاج تجديد ربط Google Health.",
        )
    except GoogleHealthError:
        return _heart_contract(
            "unavailable",
            message="تعذر جلب قراءة نبض جديدة مؤقتًا.",
        )
    except Exception:
        return _heart_contract(
            "unavailable",
            message="النبض غير متاح مؤقتًا.",
        )


BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
ALLOWED_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"
TELEGRAM_FILE_API = f"https://api.telegram.org/file/bot{BOT_TOKEN}"
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "https://web-production-45a08f.up.railway.app").rstrip("/")

# --- إعدادات إعادة الموافقة (reauth) ---
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
GOOGLE_SCOPES = (
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly "
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.writeonly "
    "https://www.googleapis.com/auth/googlehealth.location.readonly "
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly "
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly "
    "https://www.googleapis.com/auth/googlehealth.settings.readonly"
)
REAUTH_REDIRECT = f"{PUBLIC_BASE_URL}/reauth/callback"






def _reauth_state():
    """توقيع بسيط يمنع أي شخص غريب من استخدام مسار إعادة الموافقة."""
    return hmac.new(BOT_TOKEN.encode(), b"reauth-v1", hashlib.sha256).hexdigest()[:32]


def _reauth_url():
    from urllib.parse import urlencode
    params = urlencode({
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": REAUTH_REDIRECT,
        "response_type": "code",
        "scope": GOOGLE_SCOPES,
        "access_type": "offline",
        "prompt": "consent",
        "state": _reauth_state(),
    })
    return f"https://accounts.google.com/o/oauth2/v2/auth?{params}"


def send_reauth_link(chat_id, reason=""):
    prefix = f"⚠️ {reason}\n\n" if reason else ""
    send_message(
        chat_id,
        prefix + "🔑 اضغط الزر، سجّل دخولك بقوقل واضغط \"السماح\" — "
        "والبوت يستلم التوكن الجديد ويحفظه بنفسه خلال ثواني.",
        reply_markup={"inline_keyboard": [[{
            "text": "🔄 تجديد ربط Google Health",
            "url": _reauth_url(),
        }]]},
    )
GYM_MANAGE_FLOW = {}

MAIN_KEYBOARD = {
    "keyboard": [
        ["📊 ملخص اليوم", "📅 ملخص الأسبوع"],
        ["😴 تحليل النوم", "❤️ النبض"],
        ["🏃 النشاط", "⚡ الجاهزية"],
        ["🎯 خطة اليوم", "📈 التقرير الأسبوعي"],
        ["🏋️ تسجيل تمرين", "📚 سجل التمارين"],
        ["🚀 التقدم", "⚖️ توازن العضلات"],
        ["🧠 اقتراح الأوزان", "🤖 تحليل ذكي"],
    ],
    "resize_keyboard": True,
    "is_persistent": True,
    "input_field_placeholder": "اسأل مدربك الذكي أو اختر من القائمة…",
}

ARABIC_BUTTON_COMMANDS = {
    "📊 ملخص اليوم": "/today",
    "📅 ملخص الأسبوع": "/week",
    "😴 تحليل النوم": "/sleep",
    "❤️ النبض": "/heart",
    "🏃 النشاط": "/activity",
    "⚡ الجاهزية": "/readiness",
    "🎯 خطة اليوم": "/todayplan",
    "📈 التقرير الأسبوعي": "/report",
    "🏋️ تسجيل تمرين": "/gym",
    "📚 سجل التمارين": "/سجل",
    "🚀 التقدم": "/progress",
    "⚖️ توازن العضلات": "/balance",
    "🧠 اقتراح الأوزان": "/next",
    "🤖 تحليل ذكي": "/analyze",
}

WELCOME_MESSAGE = (
    "👋 <b>هلا أحمد، جاهز؟</b>\n\n"
    "أنا مدربك الشخصي المرتبط ببيانات Fitbit وسجل تمارينك.\n"
    "اختر من الأزرار تحت، أو اكتب سؤالك مباشرة للمدرب الذكي.\n\n"
    "❤️ <b>النبض</b>: لحظي + معدل الراحة\n"
    "🏋️ <b>التمارين</b>: تسجيل، تعديل، حذف وسجل كامل\n"
    "⚡ <b>الذكاء</b>: جاهزية، خطة يوم، تقدم وتوصيات أوزان"
)


# ---------------------------------------------------------------------------
# أسماء أيام وشهور مختصرة
# ---------------------------------------------------------------------------

_DAY_SHORT = {0: "إثن", 1: "ثلث", 2: "أرب", 3: "خمس",
              4: "جمع", 5: "سبت", 6: "أحد"}

_MONTH_AR = {1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
             5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
             9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر"}


def _arabic_date(date_str):
    """يحول "2026-07-08" إلى "أرب 08/07"."""
    try:
        dt = datetime.date.fromisoformat(date_str)
        return f"{_DAY_SHORT[dt.weekday()]} {dt.strftime('%d/%m')}"
    except Exception:
        return date_str


def _month_label(year, month):
    return f"📅 {_MONTH_AR[month]} {year}"


def _last_n_dates(n=365):
    """يرجع قائمة بآخر N يوم من الأحدث للأقدم."""
    today = datetime.date.today()
    return [(today - datetime.timedelta(days=i)).isoformat() for i in range(n)]


def _group_by_month(dates):
    """يجمّع قائمة تواريخ ISO حسب (سنة، شهر) من الأحدث للأقدم."""
    from collections import OrderedDict
    groups = OrderedDict()
    for d in dates:
        dt = datetime.date.fromisoformat(d)
        key = (dt.year, dt.month)
        groups.setdefault(key, []).append(d)
    return groups  # {(2026,7): ["2026-07-08", ...], (2026,6): [...]}


def _home_button():
    return {"text": "🏠 الرئيسية", "callback_data": "go_home"}


# ---------------------------------------------------------------------------
# Telegram helpers
# ---------------------------------------------------------------------------

def send_message(chat_id, text, reply_markup=None, parse_mode=None):
    data = {"chat_id": chat_id, "text": text}
    if parse_mode:
        data["parse_mode"] = parse_mode
    if reply_markup is not None:
        data["reply_markup"] = json.dumps(reply_markup)
    requests.post(f"{TELEGRAM_API}/sendMessage", data=data, timeout=15)


def edit_message(chat_id, message_id, text, reply_markup=None, parse_mode=None):
    data = {"chat_id": chat_id, "message_id": message_id, "text": text}
    if parse_mode:
        data["parse_mode"] = parse_mode
    if reply_markup is not None:
        data["reply_markup"] = json.dumps(reply_markup)
    requests.post(f"{TELEGRAM_API}/editMessageText", data=data, timeout=15)


def answer_callback(callback_query_id, text=None):
    data = {"callback_query_id": callback_query_id}
    if text:
        data["text"] = text
    try:
        requests.post(f"{TELEGRAM_API}/answerCallbackQuery", data=data, timeout=10)
    except Exception:
        pass


def send_typing(chat_id):
    try:
        requests.post(f"{TELEGRAM_API}/sendChatAction",
                      data={"chat_id": chat_id, "action": "typing"}, timeout=5)
    except Exception:
        pass


def download_voice_file(file_id):
    resp = requests.get(f"{TELEGRAM_API}/getFile", params={"file_id": file_id}, timeout=15)
    resp.raise_for_status()
    file_path = resp.json()["result"]["file_path"]
    file_resp = requests.get(f"{TELEGRAM_FILE_API}/{file_path}", timeout=20)
    file_resp.raise_for_status()
    return file_resp.content


def register_commands():
    """يسجّل قائمة الأوامر في Telegram عشان تظهر لما المستخدم يكتب /."""
    commands = [
        {"command": "start",    "description": "الرسالة الترحيبية"},
        {"command": "today",    "description": "ملخص يومي بالتاريخ"},
        {"command": "week",     "description": "ملخص آخر 7 أيام"},
        {"command": "sleep",    "description": "تحليل النوم بالتاريخ"},
        {"command": "heart",    "description": "النبض ومعدل الراحة"},
        {"command": "activity", "description": "النشاط والخطوات"},
        {"command": "analyze",  "description": "تحليل ذكي أسبوعي"},
        {"command": "gym",      "description": "سجّل تمارين الحديد"},
        {"command": "readiness", "description": "جاهزيتك اليوم من 100"},
        {"command": "todayplan", "description": "وش تسوي اليوم؟"},
        {"command": "next",      "description": "اقتراح أوزان الجلسة القادمة"},
        {"command": "progress",  "description": "تحليل التقدم والتراجع"},
        {"command": "balance",   "description": "توازن العضلات"},
        {"command": "report",    "description": "التقرير الأسبوعي"},
    ]
    try:
        requests.post(f"{TELEGRAM_API}/setMyCommands",
                      json={"commands": commands}, timeout=10)
    except Exception:
        pass


register_commands()

# ---------------------------------------------------------------------------
# أزرار اختيار التاريخ للإحصائيات
# ---------------------------------------------------------------------------

_STAT_LABELS = {
    "today":    "📊 اختر شهر للملخص:",
    "week":     "📅 اختر شهرًا ثم يوم نهاية فترة الـ7 أيام:",
    "sleep":    "😴 اختر شهر لتحليل النوم:",
    "heart":    "❤️ اختر شهر لبيانات النبض:",
    "activity": "🏃 اختر شهر لبيانات النشاط:",
    "readiness": "⚡ اختر شهر لعرض الجاهزية:",
    "todayplan": "🎯 اختر شهر لعرض الخطة:",
}


def send_date_picker(chat_id, stat_type, message_id=None):
    """المستوى ١: يعرض الشهور المتاحة (آخر 30 يوم مجمّعة)."""
    groups = _group_by_month(_last_n_dates(30))
    buttons = [
        [{"text": _month_label(y, m), "callback_data": f"stat_month:{stat_type}:{y}-{m:02d}"}]
        for (y, m) in groups
    ]
    buttons.append([_home_button()])
    markup = {"inline_keyboard": buttons}
    text = _STAT_LABELS.get(stat_type, "📅 اختر الشهر:")
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def send_month_dates(chat_id, message_id, stat_type, year_month):
    """المستوى ٢: يعرض أيام الشهر المختار — زرّين بكل صف."""
    groups = _group_by_month(_last_n_dates(30))
    y, m = int(year_month.split("-")[0]), int(year_month.split("-")[1])
    dates = groups.get((y, m), [])
    if not dates:
        edit_message(chat_id, message_id, "⚠️ ما فيه أيام بهذا الشهر.")
        return
    # زرّان بكل صف
    rows = []
    for i in range(0, len(dates), 2):
        row = [{"text": _arabic_date(dates[i]), "callback_data": f"stat_{stat_type}:{dates[i]}"}]
        if i + 1 < len(dates):
            row.append({"text": _arabic_date(dates[i+1]), "callback_data": f"stat_{stat_type}:{dates[i+1]}"})
        rows.append(row)
    rows.append([{"text": "🔙 الشهور", "callback_data": f"stat_pick:{stat_type}"}, _home_button()])
    edit_message(chat_id, message_id,
                 f"{_month_label(y, m)} — اختر اليوم:", reply_markup={"inline_keyboard": rows})


def _nav_buttons(back_cb):
    return [{"text": "🔙 رجوع", "callback_data": back_cb}, _home_button()]


def _daily_result_keyboard(stat_type, date_str, refresh_text="🔄 تحديث الآن"):
    """تنقل موحّد: السابق/التالي + تحديث فوري + اختيار تاريخ."""
    d = datetime.date.fromisoformat(date_str)
    today = datetime.date.today()
    prev_d = (d - datetime.timedelta(days=1)).isoformat()
    next_d = (d + datetime.timedelta(days=1)).isoformat()
    nav = [{"text": "◀️ اليوم السابق", "callback_data": f"stat_{stat_type}:{prev_d}"}]
    if d < today:
        nav.append({"text": "اليوم التالي ▶️", "callback_data": f"stat_{stat_type}:{next_d}"})
    return {"inline_keyboard": [
        nav,
        [
            {"text": refresh_text, "callback_data": f"stat_{stat_type}:{date_str}"},
            {"text": "📅 الأيام والشهور", "callback_data": f"stat_pick:{stat_type}"},
        ],
        [_home_button()],
    ]}


def _weekly_result_keyboard(end_date, callback_prefix="week_period"):
    d = datetime.date.fromisoformat(end_date)
    today = datetime.date.today()
    prev_end = (d - datetime.timedelta(days=7)).isoformat()
    next_end = (d + datetime.timedelta(days=7)).isoformat()
    nav = [{"text": "◀️ الأسبوع السابق", "callback_data": f"{callback_prefix}:{prev_end}"}]
    if d < today:
        nav.append({"text": "الأسبوع التالي ▶️", "callback_data": f"{callback_prefix}:{next_end}"})
    return {"inline_keyboard": [
        nav,
        [
            {"text": "🔄 تحديث الآن", "callback_data": f"{callback_prefix}:{end_date}"},
            {"text": "📅 الأيام والشهور", "callback_data": "stat_pick:week"},
        ],
        [_home_button()],
    ]}


def show_stat_today(chat_id, message_id, date_str):
    try:
        data = get_summary_by_date(date_str)
        text = format_today_message(data)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب البيانات:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("today", date_str))


def send_today_now(chat_id, message_id=None):
    date_str = datetime.date.today().isoformat()
    try:
        text = format_today_message(get_summary_by_date(date_str))
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب البيانات:\n{e}"
    markup = _daily_result_keyboard("today", date_str)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def show_stat_sleep(chat_id, message_id, date_str):
    try:
        sleep = get_sleep(date_str)
        text = format_sleep_message(sleep)
        text = text.replace("آخر ليلة", _arabic_date(date_str), 1)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النوم:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("sleep", date_str))


def send_sleep_now(chat_id, message_id=None):
    date_str = datetime.date.today().isoformat()
    try:
        sleep = get_sleep(date_str)
        text = format_sleep_message(sleep)
        text = text.replace("آخر ليلة", "نوم اليوم", 1)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النوم:\n{e}"
    markup = _daily_result_keyboard("sleep", date_str)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def _heart_now_text():
    rhr = get_resting_heart_rate()
    current = get_current_heart_rate()
    return format_heart_message(rhr, current)


def send_heart_now(chat_id, message_id=None):
    try:
        text = _heart_now_text()
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النبض:\n{e}"
    today_str = datetime.date.today().isoformat()
    markup = _daily_result_keyboard("heart", today_str, "🔄 تحديث النبض")
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def show_stat_heart(chat_id, message_id, date_str):
    try:
        today_str = datetime.date.today().isoformat()
        rhr = get_resting_heart_rate(date_str)
        current = get_current_heart_rate() if date_str == today_str else None
        text = f"❤️ النبض — {_arabic_date(date_str)}\n" + format_heart_message(rhr, current)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النبض:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("heart", date_str, "🔄 تحديث النبض"))


def show_stat_activity(chat_id, message_id, date_str):
    try:
        data = get_summary_by_date(date_str)
        text = f"🏃 النشاط — {_arabic_date(date_str)}\n" + format_activity_message(data)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النشاط:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("activity", date_str))


def send_activity_now(chat_id, message_id=None):
    date_str = datetime.date.today().isoformat()
    try:
        text = f"🏃 النشاط — اليوم\n" + format_activity_message(get_summary_by_date(date_str))
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات النشاط:\n{e}"
    markup = _daily_result_keyboard("activity", date_str)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def show_stat_readiness(chat_id, message_id, date_str):
    try:
        text = f"⚡ الجاهزية — {_arabic_date(date_str)}\n\n" + format_readiness(get_summary_by_date(date_str)).replace("جاهزيتك اليوم", "جاهزيتك")
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات الجاهزية:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("readiness", date_str))


def send_readiness_now(chat_id, message_id=None):
    date_str = datetime.date.today().isoformat()
    text = format_readiness(get_summary_by_date(date_str))
    markup = _daily_result_keyboard("readiness", date_str)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def show_stat_todayplan(chat_id, message_id, date_str):
    try:
        text = f"🎯 خطة {_arabic_date(date_str)}\n\n" + today_plan(get_summary_by_date(date_str)).replace("وش تسوي اليوم؟", "الخطة المقترحة")
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب خطة اليوم:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_daily_result_keyboard("todayplan", date_str))


def send_todayplan_now(chat_id, message_id=None):
    date_str = datetime.date.today().isoformat()
    text = today_plan(get_summary_by_date(date_str))
    markup = _daily_result_keyboard("todayplan", date_str)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def show_week_period(chat_id, message_id, end_date):
    try:
        week = get_week_summary_for(end_date)
        start_date = week[0]["date"] if week else end_date
        text = f"📅 ملخص 7 أيام\n{_arabic_date(start_date)} ← {_arabic_date(end_date)}\n\n" + format_week_message(week)
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات الأسبوع:\n{e}"
    edit_message(chat_id, message_id, text, reply_markup=_weekly_result_keyboard(end_date))


def send_week_now(chat_id, message_id=None):
    end_date = datetime.date.today().isoformat()
    try:
        text = format_week_message(get_week_summary_for(end_date))
    except GoogleHealthError as e:
        text = f"⚠️ خطأ بجلب بيانات الأسبوع:\n{e}"
    markup = _weekly_result_keyboard(end_date)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def _simple_live_markup(callback_data, extra=None):
    rows = [[{"text": "🔄 تحديث الآن", "callback_data": callback_data}]]
    if extra:
        rows.append(extra)
    rows.append([_home_button()])
    return {"inline_keyboard": rows}


def send_live_computed(chat_id, kind, message_id=None):
    send_typing(chat_id)
    if kind == "report":
        text = weekly_report(get_today_summary())
        extra = [{"text": "📚 سجل التمارين", "web_app": {"url": f"{PUBLIC_BASE_URL}/history"}}]
    elif kind == "progress":
        text = progress_report()
        extra = [{"text": "📚 السجل الكامل", "web_app": {"url": f"{PUBLIC_BASE_URL}/history"}}]
    elif kind == "balance":
        text = format_muscle_balance(7)
        extra = [{"text": "📚 السجل الكامل", "web_app": {"url": f"{PUBLIC_BASE_URL}/history"}}]
    elif kind == "next":
        text = format_next_suggestions()
        extra = [{"text": "🏋️ تسجيل تمرين", "callback_data": "back_days"}]
    elif kind == "analyze":
        text = "🤖 " + analyze_week(get_week_summary(), get_today_summary())
        extra = [{"text": "📚 السجل الكامل", "web_app": {"url": f"{PUBLIC_BASE_URL}/history"}}]
    else:
        text, extra = "⚠️ خيار غير معروف.", None
    markup = _simple_live_markup(f"live:{kind}", extra)
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


# ---------------------------------------------------------------------------
# المدرب الذكي — multi-turn
# ---------------------------------------------------------------------------

def _build_gym_context():
    try:
        dates = gym_tracker.get_workout_dates(limit=7)
        if not dates:
            return None
        lines = []
        for d in dates:
            summary = gym_tracker.get_day_summary(d)
            if not summary:
                continue
            lines.append(f"📅 {d}:")
            for item in summary:
                day_label = gym_tracker.WORKOUT_PLAN.get(item["day_key"], {}).get("label", "")
                lines.append(f"  • {item['exercise']} ({day_label})")
                for s in item["sets"]:
                    lines.append(
                        f"    - جولة {s['set_number']}: {s['reps']} تكرار × {s['weight']} كجم"
                    )
        return "\n".join(lines) if lines else None
    except Exception:
        return None


def _answer_coach_question(chat_id, question):
    send_typing(chat_id)
    try:
        week = get_week_summary()
        today = get_today_summary()
    except GoogleHealthError:
        week, today = [], {}

    gym_context = _build_gym_context()
    intelligence = coach_context(today)
    if intelligence:
        gym_context = ((gym_context + "\n\n") if gym_context else "") + "🧠 ذكاء الأداء الحالي:\n" + intelligence
    history = gym_tracker.get_history(chat_id, limit=10)

    answer = ask_coach(question, week, today, gym_context=gym_context, history=history)

    # احفظ السؤال والجواب بتاريخ المحادثة
    gym_tracker.save_message(chat_id, "user", question)
    gym_tracker.save_message(chat_id, "model", answer)

    send_message(chat_id, "🤖 " + answer)


def match_voice_command(transcribed_text):
    text = transcribed_text.strip()
    lowered = text.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    keyword_map = [
        (["الاسبوع", "أسبوع", "الأسبوع"], "/week"),
        (["نوم", "نايم"], "/sleep"),
        (["نبض", "قلب"], "/heart"),
        (["نشاط"], "/activity"),
        (["حلل", "تحليل"], "/analyze"),
        (["اليوم"], "/today"),
        (["جيم", "تمرين", "تمارين"], "/gym"),
    ]
    for keywords, command in keyword_map:
        if any(k in lowered for k in keywords):
            return command
    return text


# ---------------------------------------------------------------------------
# تتبّع تمارين الحديد
# ---------------------------------------------------------------------------

def format_last_session(last):
    if not last:
        return "📊 أول مرة تسجل هذا التمرين، بالتوفيق!"
    lines = [f"📊 آخر مرة ({last['date']}):"]
    for s in last["sets"]:
        lines.append(f"   جولة {s['set_number']}: {s['reps']} تكرار × {s['weight']} كجم")
    return "\n".join(lines)


def send_gym_days_menu(chat_id, message_id=None):
    plan = gym_tracker.get_workout_plan()
    items = list(plan.items())
    buttons = []
    for i in range(0, len(items), 2):
        row = []
        for key, info in items[i:i + 2]:
            row.append({"text": info["label"], "callback_data": f"day:{key}"})
        buttons.append(row)
    buttons.append([_home_button()])
    markup = {"inline_keyboard": buttons}
    text = "💪 <b>اختَر يوم التمرين</b>\n\nسجّل جولتك بسرعة، وعدّل برنامجك من نفس القائمة."
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup, parse_mode="HTML")
    else:
        send_message(chat_id, text, reply_markup=markup, parse_mode="HTML")


def send_exercise_menu(chat_id, message_id, day_key):
    day = gym_tracker.get_day_plan(day_key)
    if not day:
        edit_message(chat_id, message_id, "⚠️ يوم التمرين غير موجود.")
        return
    buttons = []
    for idx, ex in enumerate(day["exercises"]):
        buttons.append([{
            "text": f"{idx + 1:02d}  •  {ex}",
            "web_app": {"url": f"{PUBLIC_BASE_URL}/workout?day={day_key}&idx={idx}"},
        }])
    buttons.append([
        {"text": "➕ إضافة تمرين", "callback_data": f"manage_add:{day_key}"},
        {"text": "🗑 حذف تمرين", "callback_data": f"manage_delete:{day_key}"},
    ])
    buttons.append([{"text": "‹ رجوع للأيام", "callback_data": "back_days"}, _home_button()])
    markup = {"inline_keyboard": buttons}
    edit_message(
        chat_id, message_id,
        f"🏋️ <b>{day['label']}</b>\n\nاختَر تمرينًا لفتح شاشة التسجيل، أو عدّل القائمة من أزرار الإدارة بالأسفل.",
        reply_markup=markup, parse_mode="HTML",
    )


def send_delete_exercise_menu(chat_id, message_id, day_key):
    day = gym_tracker.get_day_plan(day_key)
    if not day:
        return send_gym_days_menu(chat_id, message_id)
    buttons = [
        [{"text": f"🗑 {idx + 1:02d}  •  {ex}", "callback_data": f"manage_delpick:{day_key}:{idx}"}]
        for idx, ex in enumerate(day["exercises"])
    ]
    buttons.append([{"text": "‹ رجوع للتمارين", "callback_data": f"day:{day_key}"}])
    edit_message(chat_id, message_id, f"🗑 <b>حذف تمرين</b>\n\nاختَر التمرين الذي تريد حذفه من برنامج {day['label']}.\n<b>ملاحظة:</b> سجلك القديم لن يُحذف.", reply_markup={"inline_keyboard": buttons}, parse_mode="HTML")


def send_delete_confirmation(chat_id, message_id, day_key, idx):
    day = gym_tracker.get_day_plan(day_key)
    if not day or idx < 0 or idx >= len(day["exercises"]):
        return send_exercise_menu(chat_id, message_id, day_key)
    ex = day["exercises"][idx]
    markup = {"inline_keyboard": [
        [{"text": "نعم، احذف التمرين", "callback_data": f"manage_delconfirm:{day_key}:{idx}"}],
        [{"text": "لا، رجوع", "callback_data": f"manage_delete:{day_key}"}],
    ]}
    edit_message(chat_id, message_id, f"⚠️ <b>تأكيد الحذف</b>\n\n{ex}\n\nسيُحذف من قائمة البرنامج فقط، وسجل التمارين السابق سيبقى محفوظًا.", reply_markup=markup, parse_mode="HTML")


# التسجيل اليدوي النصي أُلغي نهائيًا.
# جميع الأوزان والعدات تُسجّل حصريًا من Telegram Mini App،
# بينما كل رسالة نصية عادية تذهب مباشرة إلى المدرب الذكي.


# ---------------------------------------------------------------------------
# السجل التاريخي للجيم
# ---------------------------------------------------------------------------

def send_history_menu(chat_id, message_id=None):
    markup = {"inline_keyboard": [
        [{"text": "📅 عرض بالتاريخ", "callback_data": "hist_dates"}],
        [{"text": "🏋️ عرض بالتمرين", "callback_data": "hist_exlist"}],
        [_home_button()],
    ]}
    text = "📋 سجل تمارينك — اختر طريقة العرض:"
    if message_id:
        edit_message(chat_id, message_id, text, reply_markup=markup)
    else:
        send_message(chat_id, text, reply_markup=markup)


def send_history_dates(chat_id, message_id):
    dates = gym_tracker.get_workout_dates(limit=60)
    if not dates:
        edit_message(chat_id, message_id, "📭 ما فيه تمارين مسجّلة بعد. ابدأ بـ /gym!",
                     reply_markup={"inline_keyboard": [[_home_button()]]})
        return
    # نجمّع بالشهر
    groups = {}
    for d in dates:
        dt = datetime.date.fromisoformat(d)
        groups.setdefault((dt.year, dt.month), []).append(d)
    buttons = [
        [{"text": _month_label(y, m) + f" ({len(ds)} يوم)",
          "callback_data": f"hist_month:{y}-{m:02d}"}]
        for (y, m), ds in groups.items()
    ]
    buttons.append([{"text": "🔙 رجوع", "callback_data": "hist_back"}, _home_button()])
    edit_message(chat_id, message_id, "📅 اختر الشهر:", reply_markup={"inline_keyboard": buttons})


def send_history_month(chat_id, message_id, year_month):
    """يعرض أيام الشهر المختار من سجل الجيم — زرّان بكل صف."""
    y, m = int(year_month.split("-")[0]), int(year_month.split("-")[1])
    all_dates = gym_tracker.get_workout_dates(limit=60)
    dates = [d for d in all_dates
             if datetime.date.fromisoformat(d).year == y
             and datetime.date.fromisoformat(d).month == m]
    if not dates:
        edit_message(chat_id, message_id, "⚠️ ما فيه تمارين بهذا الشهر.")
        return
    rows = []
    for i in range(0, len(dates), 2):
        row = [{"text": _arabic_date(dates[i]), "callback_data": f"hist_date:{dates[i]}"}]
        if i + 1 < len(dates):
            row.append({"text": _arabic_date(dates[i+1]), "callback_data": f"hist_date:{dates[i+1]}"})
        rows.append(row)
    rows.append([{"text": "🔙 الشهور", "callback_data": "hist_dates"}, _home_button()])
    edit_message(chat_id, message_id,
                 f"{_month_label(y, m)} — اختر اليوم:", reply_markup={"inline_keyboard": rows})


def send_history_day(chat_id, message_id, date):
    summary = gym_tracker.get_day_summary(date)
    if not summary:
        edit_message(chat_id, message_id, f"⚠️ ما فيه بيانات ليوم {date}.")
        return
    dt = datetime.date.fromisoformat(date)
    lines = [f"📅 {_arabic_date(date)} — {date}\n"]
    for item in summary:
        day_label = gym_tracker.WORKOUT_PLAN.get(item["day_key"], {}).get("label", "")
        lines.append(f"🏋️ {item['exercise']}")
        if day_label:
            lines.append(f"   ({day_label})")
        for s in item["sets"]:
            lines.append(f"   جولة {s['set_number']}: {s['reps']} تكرار × {s['weight']} كجم")
        lines.append("")
    back_cb = f"hist_month:{dt.year}-{dt.month:02d}"
    markup = {"inline_keyboard": [
        [{"text": "🔙 رجوع", "callback_data": back_cb}, _home_button()],
    ]}
    edit_message(chat_id, message_id, "\n".join(lines).strip(), reply_markup=markup)


def send_history_exercises_menu(chat_id, message_id):
    done = gym_tracker.get_all_exercises_done()
    if not done:
        edit_message(chat_id, message_id, "📭 ما فيه تمارين مسجّلة بعد. ابدأ بـ /gym!",
                     reply_markup={"inline_keyboard": [[_home_button()]]})
        return
    buttons = []
    for item in done:
        day_key, exercise = item["day_key"], item["exercise"]
        plan = (gym_tracker.get_day_plan(day_key) or {}).get("exercises", [])
        try:
            idx = plan.index(exercise)
            buttons.append([{"text": exercise, "callback_data": f"hist_ex:{day_key}:{idx}"}])
        except ValueError:
            continue
    buttons.append([{"text": "🔙 رجوع", "callback_data": "hist_back"}, _home_button()])
    edit_message(chat_id, message_id, "🏋️ اختر التمرين لتشوف تاريخه:",
                 reply_markup={"inline_keyboard": buttons})


def send_history_exercise(chat_id, message_id, day_key, idx):
    exercises = (gym_tracker.get_day_plan(day_key) or {}).get("exercises", [])
    if idx >= len(exercises):
        edit_message(chat_id, message_id, "⚠️ ما لقيت هذا التمرين.")
        return
    exercise = exercises[idx]
    history = gym_tracker.get_exercise_history(day_key, exercise, limit=6)
    if not history:
        edit_message(chat_id, message_id, f"📭 ما فيه سجل لـ {exercise} بعد.")
        return
    lines = [f"🏋️ {exercise}\n"]
    for session in history:
        lines.append(f"📅 {_arabic_date(session['date'])} — {session['date']}:")
        for s in session["sets"]:
            lines.append(f"   جولة {s['set_number']}: {s['reps']} تكرار × {s['weight']} كجم")
        lines.append("")
    markup = {"inline_keyboard": [
        [{"text": "🔙 التمارين", "callback_data": "hist_exlist"}, _home_button()],
    ]}
    edit_message(chat_id, message_id, "\n".join(lines).strip(), reply_markup=markup)


# ---------------------------------------------------------------------------
# معالج الأوامر
# ---------------------------------------------------------------------------

def handle_command(chat_id, text):
    try:
        text = ARABIC_BUTTON_COMMANDS.get(text, text)
        if text == "/start":
            send_message(chat_id, WELCOME_MESSAGE, reply_markup=MAIN_KEYBOARD, parse_mode="HTML")

        elif text in ("/reauth", "/تجديد"):
            updated = token_store.token_updated_at()
            note = f"آخر تجديد: {updated} UTC" if updated else "ما فيه توكن محفوظ بقاعدة البيانات بعد."
            send_reauth_link(chat_id, reason=note)

        elif text in ("/تمرين", "/gym"):
            send_gym_days_menu(chat_id)

        elif text in ("/سجل", "/log", "/history"):
            send_message(
                chat_id,
                "📚 <b>سجل التمارين</b>\n\nافتح السجل الاحترافي لتعديل أو حذف أي جولة قديمة. أي تغيير تحفظه هنا ينعكس مباشرة على تحليلات المدرب الذكي.",
                reply_markup={"inline_keyboard": [[{
                    "text": "فتح سجل التمارين",
                    "web_app": {"url": f"{PUBLIC_BASE_URL}/history"},
                }]]},
                parse_mode="HTML",
            )

        elif text in ("/مسح", "/clear", "/reset"):
            gym_tracker.clear_history(chat_id)
            send_message(chat_id, "🗑️ تم مسح تاريخ المحادثة. ابدأ سؤال جديد!")

        elif text == "/today":
            send_today_now(chat_id)

        elif text == "/week":
            send_week_now(chat_id)

        elif text == "/sleep":
            send_sleep_now(chat_id)

        elif text == "/heart":
            send_heart_now(chat_id)

        elif text == "/activity":
            send_activity_now(chat_id)

        elif text == "/readiness":
            send_readiness_now(chat_id)

        elif text in ("/todayplan", "/وش_اسوي_اليوم"):
            send_todayplan_now(chat_id)

        elif text == "/next":
            send_live_computed(chat_id, "next")

        elif text == "/progress":
            send_live_computed(chat_id, "progress")

        elif text == "/balance":
            send_live_computed(chat_id, "balance")

        elif text == "/report":
            send_live_computed(chat_id, "report")

        elif text == "/analyze":
            send_live_computed(chat_id, "analyze")

        elif text.startswith("/coach"):
            question = text[len("/coach"):].strip()
            if not question:
                send_message(chat_id, "اكتب سؤالك بعد الأمر، مثال:\n/coach ليش نومي متقطع؟")
            else:
                _answer_coach_question(chat_id, question)

        elif text.startswith("/"):
            send_message(chat_id, "🤔 ما عرفت هذا الأمر. اضغط أحد الأزرار العربية تحت، أو اكتب /start.", reply_markup=MAIN_KEYBOARD)

        else:
            _answer_coach_question(chat_id, text)

    except TokenExpiredError:
        send_reauth_link(chat_id, reason="توكن Google انتهى (تجديد أسبوعي معتاد).")
    except GoogleHealthError as e:
        send_message(chat_id, f"⚠️ خطأ بجلب بياناتك من Google Health:\n{e}")
    except AICoachError as e:
        send_message(chat_id, f"⚠️ خطأ بالمدرب الذكي:\n{e}")
    except Exception as e:
        send_message(chat_id, f"⚠️ خطأ غير متوقع:\n{e}")


# ---------------------------------------------------------------------------
# Telegram Mini App — إدخال الوزن والعدات بخانتين
# ---------------------------------------------------------------------------

def _validate_telegram_init_data(init_data):
    """يتحقق من توقيع Telegram Web App ويرجع بيانات المستخدم إذا كانت صحيحة."""
    if not init_data or not BOT_TOKEN:
        return None
    try:
        pairs = dict(parse_qsl(init_data, keep_blank_values=True))
        received_hash = pairs.pop("hash", "")
        if not received_hash:
            return None
        auth_date = int(pairs.get("auth_date", "0"))
        if not auth_date or abs(int(time.time()) - auth_date) > 86400:
            return None
        data_check_string = "\n".join(f"{k}={pairs[k]}" for k in sorted(pairs))
        secret_key = hmac.new(b"WebAppData", BOT_TOKEN.encode(), hashlib.sha256).digest()
        expected_hash = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_hash, received_hash):
            return None
        user = json.loads(pairs.get("user", "{}"))
        if str(user.get("id", "")) != str(ALLOWED_CHAT_ID):
            return None
        return user
    except Exception:
        return None


def _resolve_exercise(day_key, idx):
    day = gym_tracker.get_day_plan(day_key)
    if not day:
        return None, None
    try:
        idx = int(idx)
    except (TypeError, ValueError):
        return None, None
    exercises = day.get("exercises", [])
    if idx < 0 or idx >= len(exercises):
        return None, None
    return day, exercises[idx]


@app.route("/")
def home():
    return Response(
        """<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Fitbit Gym Bot</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#101218;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0;text-align:center">
        <div><div style="font-size:54px">🏋️</div><h2>Fitbit Gym Bot شغال ✅</h2><p style="opacity:.7">افتح تسجيل التمرين من داخل البوت في Telegram.</p></div>
        </body></html>""",
        mimetype="text/html",
    )


@app.route("/workout")
def workout_mini_app():
    html_path = os.path.join(os.path.dirname(__file__), "workout.html")
    with open(html_path, "r", encoding="utf-8") as f:
        return Response(f.read(), mimetype="text/html")


def _miniapp_auth():
    init_data = request.headers.get("X-Telegram-Init-Data", "")
    user = _validate_telegram_init_data(init_data)
    if not user:
        return None, (jsonify({"error": "افتح الصفحة من داخل البوت في Telegram."}), 401)
    return str(user["id"]), None


@app.route("/api/workout/context")
def workout_context():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    day_key, idx = request.args.get("day"), request.args.get("idx")
    day, exercise = _resolve_exercise(day_key, idx)
    if not exercise:
        return jsonify({"error": "التمرين غير موجود."}), 400
    gym_tracker.start_exercise(chat_id, day_key, exercise)
    pending = gym_tracker.get_pending(chat_id)
    last = gym_tracker.get_last_session(day_key, exercise)
    rec = recommend_next_weight(day_key, exercise)
    info_parts = []
    if last:
        lines = [f"📊 آخر مرة ({last['date']}):"]
        lines.extend(f"جولة {x['set_number']}: {x['weight']} كجم × {x['reps']}" for x in last["sets"])
        info_parts.append("\n".join(lines))
    else:
        info_parts.append("📊 أول مرة تسجل هذا التمرين، بالتوفيق!")
    if rec:
        info_parts.append(f"🎯 اقتراحي: {rec['text']}\n📈 {rec['trend']['text']}")
    return jsonify({"day_label": day["label"], "exercise": exercise, "next_set": pending["set_number"] if pending else 1, "today_sets": gym_tracker.get_today_sets(day_key, exercise), "info": "\n\n".join(info_parts)})


@app.route("/api/workout/set", methods=["POST"])
def workout_save_set():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    day_key, idx = payload.get("day"), payload.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    if not exercise:
        return jsonify({"error": "التمرين غير موجود."}), 400
    try:
        reps, weight = int(payload.get("reps")), float(payload.get("weight"))
        if reps < 1 or reps > 999 or weight < 0 or weight > 1000:
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "تأكد من الوزن والعدات."}), 400
    pending = gym_tracker.get_pending(chat_id)
    if not pending or pending["day_key"] != day_key or pending["exercise"] != exercise:
        gym_tracker.start_exercise(chat_id, day_key, exercise)
    set_number = gym_tracker.record_set(chat_id, reps, weight)
    if set_number is None:
        return jsonify({"error": "ما قدرت أبدأ تسجيل التمرين."}), 409
    pr_events = detect_pr(day_key, exercise, reps, weight, set_number=set_number)
    for event in pr_events:
        gym_tracker.save_pr(chat_id, day_key, exercise, event)
    pending = gym_tracker.get_pending(chat_id)
    today_sets = gym_tracker.get_today_sets(day_key, exercise)
    try:
        pr_text = ("\n" + "\n".join(pr_events)) if pr_events else ""
        send_message(chat_id, f"✅ جولة {set_number}: {reps} تكرار × {weight:g} كجم{pr_text}")
    except Exception:
        pass
    return jsonify({"ok": True, "saved_set": set_number, "next_set": pending["set_number"] if pending else set_number + 1, "today_sets": today_sets, "pr_events": pr_events})


@app.route("/api/workout/edit", methods=["POST"])
def workout_edit_set():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    day_key, idx = payload.get("day"), payload.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    if not exercise:
        return jsonify({"error": "التمرين غير موجود."}), 400
    try:
        set_number = int(payload.get("set_number"))
        reps = int(payload.get("reps"))
        weight = float(payload.get("weight"))
        if set_number < 1 or reps < 1 or reps > 999 or weight < 0 or weight > 1000:
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "تأكد من بيانات الجولة."}), 400
    if not gym_tracker.update_set(day_key, exercise, set_number, reps, weight):
        return jsonify({"error": "ما لقيت الجولة المطلوب تعديلها."}), 404
    return jsonify({"ok": True, "updated_set": set_number, "today_sets": gym_tracker.get_today_sets(day_key, exercise)})


@app.route("/api/workout/undo", methods=["POST"])
def workout_undo():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    day_key, idx = payload.get("day"), payload.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    if not exercise:
        return jsonify({"error": "التمرين غير موجود."}), 400
    pending = gym_tracker.get_pending(chat_id)
    if not pending or pending["day_key"] != day_key or pending["exercise"] != exercise:
        gym_tracker.start_exercise(chat_id, day_key, exercise)
    removed = gym_tracker.undo_last_set(chat_id)
    if removed is None:
        return jsonify({"error": "ما فيه جولة سابقة أحذفها."}), 409
    pending = gym_tracker.get_pending(chat_id)
    return jsonify({"ok": True, "message": f"↩️ تم حذف الجولة {removed}.", "next_set": pending["set_number"] if pending else 1, "today_sets": gym_tracker.get_today_sets(day_key, exercise)})


@app.route("/api/workout/finish", methods=["POST"])
def workout_finish():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    day_key, idx = payload.get("day"), payload.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    if not exercise:
        return jsonify({"error": "التمرين غير موجود."}), 400
    sets = gym_tracker.get_today_sets(day_key, exercise)
    gym_tracker.clear_pending(chat_id)
    if sets:
        try:
            send_message(chat_id, f"🏁 انتهيت من {exercise}. تم حفظ {len(sets)} جولة ✅")
        except Exception:
            pass
        return jsonify({"ok": True, "message": f"تم حفظ {len(sets)} جولة ✅"})
    return jsonify({"ok": True, "message": "تم الإنهاء بدون جولات جديدة."})



@app.route("/history")
def history_mini_app():
    html_path = os.path.join(os.path.dirname(__file__), "history.html")
    with open(html_path, "r", encoding="utf-8") as f:
        return Response(f.read(), mimetype="text/html")


@app.route("/api/history")
def history_data():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    try:
        limit = max(1, min(int(request.args.get("limit", 90)), 365))
    except (TypeError, ValueError):
        limit = 90
    records = gym_tracker.get_history_records(limit_dates=limit)
    plan = gym_tracker.get_workout_plan()
    labels = {k: v.get("label", k) for k, v in plan.items()}
    for day in records:
        for ex in day["exercises"]:
            ex["day_label"] = labels.get(ex["day_key"], ex["day_key"])
    return jsonify({"ok": True, "records": records})


@app.route("/api/history/edit", methods=["POST"])
def history_edit_set():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    try:
        set_id = int(payload.get("id"))
        reps = int(payload.get("reps"))
        weight = float(payload.get("weight"))
        if set_id < 1 or reps < 1 or reps > 999 or weight < 0 or weight > 1000:
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "تأكد من الوزن والعدات."}), 400
    if not gym_tracker.update_history_set(set_id, reps, weight):
        return jsonify({"error": "ما لقيت الجولة المطلوبة."}), 404
    return jsonify({"ok": True, "message": "تم حفظ التعديل. المدرب الذكي سيقرأ البيانات الجديدة تلقائيًا."})


@app.route("/api/history/delete", methods=["POST"])
def history_delete_set():
    chat_id, error = _miniapp_auth()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    try:
        set_id = int(payload.get("id"))
        if set_id < 1:
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "الجولة غير صالحة."}), 400
    if not gym_tracker.delete_history_set(set_id):
        return jsonify({"error": "ما لقيت الجولة المطلوبة."}), 404
    return jsonify({"ok": True, "message": "تم حذف الجولة وتحديث السجل."})

# ---------------------------------------------------------------------------
# Webhook
# ---------------------------------------------------------------------------

@app.route("/webhook/<token>", methods=["POST"])
def telegram_webhook(token):
    if token != BOT_TOKEN:
        return jsonify({"ok": False}), 403

    update = request.get_json(silent=True) or {}

    callback = update.get("callback_query")
    if callback:
        cb_chat_id = str(callback.get("message", {}).get("chat", {}).get("id", ""))
        if cb_chat_id != str(ALLOWED_CHAT_ID):
            return jsonify({"ok": True})

        message_id = callback["message"]["message_id"]
        data = callback.get("data", "")
        answer_callback(callback["id"])

        try:
            # --- رئيسية ---
            if data == "go_home":
                edit_message(cb_chat_id, message_id, "🏠 الرئيسية")
                send_message(cb_chat_id, WELCOME_MESSAGE, reply_markup=MAIN_KEYBOARD, parse_mode="HTML")

            # --- اختيار تاريخ للإحصائيات ---
            elif data == "heart_now":
                send_heart_now(cb_chat_id, message_id=message_id)

            elif data.startswith("week_period:"):
                show_week_period(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("live:"):
                send_live_computed(cb_chat_id, data.split(":", 1)[1], message_id=message_id)

            elif data.startswith("stat_pick:"):
                send_date_picker(cb_chat_id, data.split(":", 1)[1], message_id=message_id)

            elif data.startswith("stat_month:"):
                # stat_month:<type>:<YYYY-MM>
                parts = data.split(":", 2)
                send_month_dates(cb_chat_id, message_id, parts[1], parts[2])

            elif data.startswith("stat_week:"):
                show_week_period(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_today:"):
                show_stat_today(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_sleep:"):
                show_stat_sleep(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_heart:"):
                show_stat_heart(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_activity:"):
                show_stat_activity(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_readiness:"):
                show_stat_readiness(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("stat_todayplan:"):
                show_stat_todayplan(cb_chat_id, message_id, data.split(":", 1)[1])

            # --- تمارين الحديد ---
            elif data == "back_days":
                send_gym_days_menu(cb_chat_id, message_id=message_id)

            elif data.startswith("day:"):
                send_exercise_menu(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("manage_add:"):
                day_key = data.split(":", 1)[1]
                day = gym_tracker.get_day_plan(day_key)
                GYM_MANAGE_FLOW[cb_chat_id] = {"action": "add", "day_key": day_key}
                edit_message(cb_chat_id, message_id, f"➕ <b>إضافة تمرين</b>\n\nأرسل الآن اسم التمرين الجديد لإضافته إلى:\n{day['label'] if day else day_key}\n\nمثال: <code>كيبل فلاي علوي (High Cable Fly)</code>", reply_markup={"inline_keyboard": [[{"text": "إلغاء", "callback_data": f"day:{day_key}"}]]}, parse_mode="HTML")

            elif data.startswith("manage_delete:"):
                GYM_MANAGE_FLOW.pop(cb_chat_id, None)
                send_delete_exercise_menu(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("manage_delpick:"):
                _, day_key, idx = data.split(":")
                send_delete_confirmation(cb_chat_id, message_id, day_key, int(idx))

            elif data.startswith("manage_delconfirm:"):
                _, day_key, idx = data.split(":")
                day = gym_tracker.get_day_plan(day_key)
                idx = int(idx)
                if day and 0 <= idx < len(day["exercises"]):
                    exercise = day["exercises"][idx]
                    gym_tracker.delete_exercise(day_key, exercise)
                send_exercise_menu(cb_chat_id, message_id, day_key)

            elif data.startswith("more_ex:"):
                send_exercise_menu(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data == "done_gym":
                edit_message(cb_chat_id, message_id,
                             "💪 أحسنت! تم حفظ جلستك.\nاضغط /gym لجلسة جديدة.",
                             reply_markup={"inline_keyboard": [[_home_button()]]})

            # --- السجل التاريخي ---
            elif data == "hist_back":
                send_history_menu(cb_chat_id, message_id=message_id)

            elif data == "hist_dates":
                send_history_dates(cb_chat_id, message_id)

            elif data.startswith("hist_month:"):
                send_history_month(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data.startswith("hist_date:"):
                send_history_day(cb_chat_id, message_id, data.split(":", 1)[1])

            elif data == "hist_exlist":
                send_history_exercises_menu(cb_chat_id, message_id)

            elif data.startswith("hist_ex:"):
                _, day_key, idx = data.split(":")
                send_history_exercise(cb_chat_id, message_id, day_key, int(idx))

        except Exception as e:
            send_message(cb_chat_id, f"⚠️ خطأ: {e}")

        return jsonify({"ok": True})

    message = update.get("message", {})
    chat_id = str(message.get("chat", {}).get("id", ""))
    text = (message.get("text") or "").strip()
    voice = message.get("voice") or message.get("audio")

    if chat_id != str(ALLOWED_CHAT_ID):
        return jsonify({"ok": True})

    if voice:
        try:
            send_typing(chat_id)
            audio_bytes = download_voice_file(voice["file_id"])
            mime_type = voice.get("mime_type", "audio/ogg")
            transcribed = transcribe_audio(audio_bytes, mime_type=mime_type)
            command = match_voice_command(transcribed)
            send_message(chat_id, f"🎙️ فهمت منك: \"{transcribed}\"")
            handle_command(chat_id, command)
        except AICoachError as e:
            send_message(chat_id, f"⚠️ ما قدرت أفهم الرسالة الصوتية:\n{e}")
        except Exception as e:
            send_message(chat_id, f"⚠️ خطأ بمعالجة الصوت:\n{e}")
        return jsonify({"ok": True})

    if text:
        flow = GYM_MANAGE_FLOW.get(chat_id) if not text.startswith("/") else None
        if flow and flow.get("action") == "add":
            try:
                day_key = flow["day_key"]
                added = gym_tracker.add_exercise(day_key, text)
                GYM_MANAGE_FLOW.pop(chat_id, None)
                day = gym_tracker.get_day_plan(day_key)
                send_message(chat_id, f"✅ تم إضافة <b>{added}</b> إلى {day['label']}.\n\nافتح /gym وستجده في آخر القائمة.", parse_mode="HTML")
            except ValueError as e:
                send_message(chat_id, f"⚠️ {e}\n\nأرسل اسمًا مختلفًا أو اضغط /gym للإلغاء.")
            return jsonify({"ok": True})
        # التسجيل النصي للوزن والعدات أُلغي نهائيًا.
        # كل رسالة نصية — حتى أثناء وجود تمرين مفتوح في Mini App — تذهب هنا
        # إلى الأوامر أو المدرب الذكي، ولا يمكن تفسيرها كجولة تمرين.
        handle_command(chat_id, text)

    return jsonify({"ok": True})


@app.route("/reauth/callback")
def reauth_callback():
    """يستقبل كود جوجل بعد موافقتك، يبدله بتوكنات، ويحفظ refresh token تلقائيًا."""
    if request.args.get("state") != _reauth_state():
        return Response("رابط غير صالح.", status=403, mimetype="text/plain; charset=utf-8")

    error = request.args.get("error")
    if error:
        return Response(f"جوجل رفضت الطلب: {error}", status=400,
                        mimetype="text/plain; charset=utf-8")

    code = request.args.get("code")
    if not code:
        return Response("ما وصل كود من جوجل.", status=400,
                        mimetype="text/plain; charset=utf-8")

    resp = requests.post("https://oauth2.googleapis.com/token", data={
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": REAUTH_REDIRECT,
        "grant_type": "authorization_code",
    }, timeout=15)

    if resp.status_code != 200:
        return Response(
            f"فشل تبديل الكود بتوكن ({resp.status_code}): {resp.text[:200]}",
            status=500, mimetype="text/plain; charset=utf-8",
        )

    data = resp.json()
    refresh = data.get("refresh_token")
    if not refresh:
        return Response(
            "جوجل ما رجعت refresh token — جرب الرابط مرة ثانية من البوت.",
            status=500, mimetype="text/plain; charset=utf-8",
        )

    token_store.save_refresh_token(refresh)
    # نظف كاش access token القديم عشان الطلب الجاي يستخدم الجديد فورًا
    try:
        from google_health_client import _token_cache
        _token_cache["access_token"] = None
        _token_cache["expires_at"] = 0
    except Exception:
        pass

    try:
        send_message(ALLOWED_CHAT_ID, "✅ تم تجديد ربط Google Health بنجاح! التوكن الجديد محفوظ ويشتغل تلقائيًا.")
    except Exception:
        pass

    html = (
        "<html dir='rtl'><head><meta charset='utf-8'>"
        "<style>body{font-family:sans-serif;text-align:center;padding:60px;"
        "background:#0f1420;color:#e8ecf4}h1{color:#4ade80}</style></head>"
        "<body><h1>✅ تم التجديد بنجاح</h1>"
        "<p>التوكن الجديد انحفظ تلقائيًا. تقدر تسكر هذي الصفحة وترجع للبوت.</p>"
        "</body></html>"
    )
    return Response(html, mimetype="text/html; charset=utf-8")


@app.route("/cron/daily")
def cron_daily():
    """تستدعيها خدمة Cron عبر curl — تشغّل الملخص الصباحي داخل خدمة الويب
    (عشان تشوف قاعدة البيانات والتوكن المحدث)."""
    if request.args.get("key") != _reauth_state():
        return Response("مفتاح غير صالح.", status=403, mimetype="text/plain; charset=utf-8")
    try:
        import daily_summary
        daily_summary.main()
        return "OK", 200
    except TokenExpiredError:
        send_reauth_link(ALLOWED_CHAT_ID, reason="توكن Google انتهى — ما قدرت أرسل ملخص الصباح.")
        return "TOKEN_EXPIRED", 200
    except Exception as e:
        return Response(f"ERR: {e}", status=500, mimetype="text/plain; charset=utf-8")


@app.route("/cron/alerts")
def cron_alerts():
    """تستدعيها خدمة Cron عبر curl — تشغّل التنبيهات الذكية داخل خدمة الويب."""
    if request.args.get("key") != _reauth_state():
        return Response("مفتاح غير صالح.", status=403, mimetype="text/plain; charset=utf-8")
    try:
        import smart_alerts
        smart_alerts.main()
        return "OK", 200
    except TokenExpiredError:
        send_reauth_link(ALLOWED_CHAT_ID, reason="توكن Google انتهى — التنبيهات متوقفة لين تجدد.")
        return "TOKEN_EXPIRED", 200
    except Exception as e:
        return Response(f"ERR: {e}", status=500, mimetype="text/plain; charset=utf-8")


@app.route("/cron/key")
def cron_key():
    """يعرض مفتاح الـ cron مرة وحدة لصاحب البوت فقط (تفتحه بنفسك وتنسخ المفتاح)."""
    # حماية بسيطة: يرسل المفتاح لتلقرامك بدل عرضه للعامة
    try:
        send_message(ALLOWED_CHAT_ID, f"🔐 مفتاح خدمات Cron:\n{_reauth_state()}")
    except Exception:
        pass
    return "أرسلت المفتاح لتلقرامك.", 200


@app.route("/ping")
def ping():
    return "OK", 200


# ---------------------------------------------------------------------------
# FitbitAir iOS Owner API — تطبيق شخصي لمستخدم واحد
# ---------------------------------------------------------------------------
IOS_API_KEY = os.environ.get("IOS_API_KEY", "b84jNwJO_Th6i0aRPYFQF7f69LnOXHsjOhhW6-LMjwdGgpH4")

def _ios_auth():
    auth = request.headers.get("Authorization", "")
    token = auth[7:] if auth.startswith("Bearer ") else request.headers.get("X-IOS-API-Key", "")
    if not token or not hmac.compare_digest(str(token), str(IOS_API_KEY)):
        return jsonify({"error": "غير مصرح"}), 401
    return None

def _sleep_minutes_ios(data):
    sleep = (data or {}).get("sleep") or {}
    summary = sleep.get("summary") or {}
    for k in ("minutesAsleep", "totalSleepMinutes", "sleepDurationMinutes"):
        v = summary.get(k)
        if v is not None:
            try: return int(v)
            except Exception: pass
    start, end = sleep.get("_local_start"), sleep.get("_local_end")
    if start and end:
        try: return max(0, int((end-start).total_seconds()//60))
        except Exception: pass
    return None

def _current_hr_ios(value):
    if not value: return (None, None)
    try:
        bpm, when = value
        return int(bpm), when.isoformat() if hasattr(when, "isoformat") else str(when or "")
    except Exception:
        return (None, None)

def _dashboard_payload(date_str=None):
    data = get_summary_by_date(date_str) if date_str else get_today_summary()
    bpm, hr_time = _current_hr_ios(data.get("current_hr"))
    try: readiness = format_readiness(data)
    except Exception as e: readiness = f"تعذر حساب الجاهزية: {e}"
    try: plan = today_plan(data)
    except Exception as e: plan = f"تعذر إنشاء الخطة: {e}"
    return {
        "date": data.get("date"), "steps": data.get("steps"), "calories": data.get("calories"),
        "resting_hr": data.get("heart_rate"), "current_hr": bpm, "current_hr_time": hr_time,
        "sleep_minutes": _sleep_minutes_ios(data), "readiness": readiness, "today_plan": plan
    }

@app.route("/api/ios/dashboard")
def ios_dashboard():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date")
        force = request.args.get("force") == "1"
        key = f"dashboard:{date_str or 'today'}"
        ttl = 45 if not date_str else 600
        payload = None if force else _cache_get(key, ttl)
        cache_hit = payload is not None

        if payload is None:
            started = time.monotonic()
            payload = _dashboard_payload(date_str)
            payload["_server_ms"] = int((time.monotonic() - started) * 1000)
            payload["_updated_at"] = datetime.datetime.utcnow().isoformat()
            _cache_set(key, payload)

        return jsonify({"ok": True, "dashboard": payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/ios/week")
def ios_week():
    err = _ios_auth()
    if err: return err
    try: return jsonify({"ok": True, "days": get_week_summary_for(request.args.get("end"))})
    except Exception as e: return jsonify({"error": str(e)}), 500


def _sleep_stage_key(raw_type):
    raw = str(raw_type or "").lower()
    if "deep" in raw or "slow" in raw:
        return "deep"
    if "rem" in raw:
        return "rem"
    if "awake" in raw or "wake" in raw:
        return "awake"
    return "light"


def _round_sleep_minutes(total_seconds):
    try:
        seconds = max(0, int(total_seconds or 0))
    except Exception:
        seconds = 0
    return int((seconds + 30) // 60)


def _sleep_details_ios(sleep):
    if not sleep:
        return None

    total = _sleep_minutes_ios({"sleep": sleep})
    bucket_seconds = {"deep": 0, "light": 0, "rem": 0, "awake": 0}
    stages = []

    for stage in sleep.get("_stages_timeline", []) or []:
        stage_type = _sleep_stage_key(stage.get("type"))
        start = stage.get("start")
        end = stage.get("end")

        duration_seconds = stage.get("duration_seconds")
        if duration_seconds is None and start and end:
            try:
                duration_seconds = max(0, int(round((end - start).total_seconds())))
            except Exception:
                duration_seconds = 0

        try:
            duration_seconds = max(0, int(duration_seconds or 0))
        except Exception:
            duration_seconds = 0

        bucket_seconds[stage_type] += duration_seconds

        if start and end:
            stages.append({
                "type": stage_type,
                "start": start.isoformat() if hasattr(start, "isoformat") else str(start),
                "end": end.isoformat() if hasattr(end, "isoformat") else str(end),
                "duration_minutes": _round_sleep_minutes(duration_seconds),
            })

    start = sleep.get("_local_start")
    end = sleep.get("_local_end")

    return {
        "start": start.isoformat() if hasattr(start, "isoformat") else None,
        "end": end.isoformat() if hasattr(end, "isoformat") else None,
        "total_minutes": total,
        "deep_minutes": _round_sleep_minutes(bucket_seconds["deep"]),
        "light_minutes": _round_sleep_minutes(bucket_seconds["light"]),
        "rem_minutes": _round_sleep_minutes(bucket_seconds["rem"]),
        "awake_minutes": _round_sleep_minutes(bucket_seconds["awake"]),
        "stages": stages,
    }

@app.route("/api/ios/connection")
def ios_connection():
    err = _ios_auth()
    if err: return err
    connected, needs_reauth = False, False
    message = "الاتصال غير متاح"
    try:
        get_access_token()
        connected = True
        message = "Google Health متصل وجاهز"
    except TokenExpiredError:
        needs_reauth = True
        message = "انتهت صلاحية الربط ويحتاج تجديد"
    except Exception as e:
        message = str(e)
    return jsonify({
        "ok": True,
        "connected": connected,
        "needs_reauth": needs_reauth,
        "token_updated_at": token_store.token_updated_at(),
        "reauth_url": _reauth_url(),
        "message": message,
    })

@app.route("/api/ios/connection/token", methods=["POST"])
def ios_connection_token():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    refresh = (x.get("refresh_token") or "").strip()
    if len(refresh) < 20:
        return jsonify({"error": "التوكن غير صالح"}), 400
    token_store.save_refresh_token(refresh)
    try:
        from google_health_client import _token_cache
        _token_cache["access_token"] = None
        _token_cache["expires_at"] = 0
        get_access_token()
        connected, needs_reauth, message = True, False, "تم حفظ التوكن والاتصال بنجاح"
    except TokenExpiredError:
        connected, needs_reauth, message = False, True, "تم الحفظ لكن التوكن يحتاج موافقة جديدة"
    except Exception as e:
        connected, needs_reauth, message = False, False, str(e)
    return jsonify({
        "ok": True,
        "connected": connected,
        "needs_reauth": needs_reauth,
        "token_updated_at": token_store.token_updated_at(),
        "reauth_url": _reauth_url(),
        "message": message,
    })



def _token_service(service_id, name, status, message, *, updated_at=None,
                   can_auto_refresh=False, external_action_required=False,
                   renewal_mode="check_only"):
    return {
        "id": service_id,
        "name": name,
        "status": status,
        "message": message,
        "updated_at": updated_at,
        "can_auto_refresh": bool(can_auto_refresh),
        "external_action_required": bool(external_action_required),
        "renewal_mode": renewal_mode,
    }


def _check_telegram_token():
    if not BOT_TOKEN:
        return _token_service(
            "telegram_bot", "Telegram Bot", "missing",
            "TELEGRAM_BOT_TOKEN غير موجود في Railway.",
            external_action_required=True,
            renewal_mode="botfather",
        )
    try:
        resp = requests.get(f"https://api.telegram.org/bot{BOT_TOKEN}/getMe", timeout=10)
        data = resp.json() if resp.content else {}
        if resp.status_code == 200 and data.get("ok"):
            username = ((data.get("result") or {}).get("username") or "البوت")
            return _token_service(
                "telegram_bot", "Telegram Bot", "ok",
                f"التوكن صالح ومتصل بـ @{username}.",
                renewal_mode="non_expiring",
            )
        return _token_service(
            "telegram_bot", "Telegram Bot", "invalid",
            "توكن Telegram غير صالح أو تم إلغاؤه من BotFather.",
            external_action_required=True,
            renewal_mode="botfather",
        )
    except requests.RequestException:
        return _token_service(
            "telegram_bot", "Telegram Bot", "unavailable",
            "تعذر الوصول إلى Telegram الآن؛ لم يتم تغيير التوكن.",
            renewal_mode="check_only",
        )


def _check_gemini_key(api_key=None):
    key = (api_key or token_store.get_gemini_api_key() or "").strip()
    updated = token_store.token_updated_at("gemini_api_key")
    if not key:
        return _token_service(
            "gemini_api", "Gemini API", "missing",
            "GEMINI_API_KEY غير موجود.",
            updated_at=updated,
            external_action_required=True,
            renewal_mode="manual_replace",
        )
    try:
        resp = requests.get(
            "https://generativelanguage.googleapis.com/v1beta/models",
            params={"key": key},
            timeout=12,
        )
        if resp.status_code == 200:
            return _token_service(
                "gemini_api", "Gemini API", "ok",
                "المفتاح صالح والمدرب الذكي جاهز.",
                updated_at=updated,
                renewal_mode="non_expiring",
            )
        return _token_service(
            "gemini_api", "Gemini API", "invalid",
            f"المفتاح مرفوض من Gemini ({resp.status_code}).",
            updated_at=updated,
            external_action_required=True,
            renewal_mode="manual_replace",
        )
    except requests.RequestException:
        return _token_service(
            "gemini_api", "Gemini API", "unavailable",
            "تعذر الوصول إلى Gemini الآن؛ لم يتم تغيير المفتاح.",
            updated_at=updated,
            renewal_mode="check_only",
        )


def _token_center_payload(force_google=False):
    services = []

    services.append(_token_service(
        "railway", "Railway", "ok", "الخادم يعمل ويستقبل طلبات التطبيق.",
        renewal_mode="not_required",
    ))

    if force_google:
        try:
            from google_health_client import _token_cache
            _token_cache["access_token"] = None
            _token_cache["expires_at"] = 0
        except Exception:
            pass

    google_needs_reauth = False
    try:
        get_access_token()
        services.append(_token_service(
            "google_health", "Google Health", "ok",
            "تم فحص وتجديد Access Token تلقائيًا.",
            updated_at=token_store.token_updated_at("google_refresh_token"),
            can_auto_refresh=True,
            renewal_mode="oauth_refresh",
        ))
    except TokenExpiredError:
        google_needs_reauth = True
        services.append(_token_service(
            "google_health", "Google Health", "reauth",
            "Refresh Token انتهى؛ اضغط إعادة ربط Google وأكمل السماح.",
            updated_at=token_store.token_updated_at("google_refresh_token"),
            can_auto_refresh=True,
            external_action_required=True,
            renewal_mode="oauth_reauth",
        ))
    except Exception as exc:
        services.append(_token_service(
            "google_health", "Google Health", "unavailable",
            f"تعذر فحص Google Health: {str(exc)[:120]}",
            updated_at=token_store.token_updated_at("google_refresh_token"),
            can_auto_refresh=True,
            renewal_mode="oauth_refresh",
        ))

    google_client_ok = bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)
    services.append(_token_service(
        "google_oauth_client", "Google OAuth Client",
        "ok" if google_client_ok else "missing",
        "Client ID وClient Secret موجودان." if google_client_ok else "بيانات Google OAuth ناقصة في Railway.",
        external_action_required=not google_client_ok,
        renewal_mode="non_expiring",
    ))

    services.append(_check_telegram_token())
    services.append(_check_gemini_key())
    services.append(_token_service(
        "ios_api", "iPhone API Key", "ok",
        "مفتاح التطبيق صالح؛ هذا الطلب وصل للخادم بنجاح.",
        renewal_mode="non_expiring",
    ))

    healthy = sum(1 for item in services if item["status"] == "ok")
    attention = len(services) - healthy
    summary = (
        f"كل الخدمات سليمة ({healthy}/{len(services)})."
        if attention == 0 else
        f"تم الفحص: {healthy} سليمة و{attention} تحتاج انتباه."
    )
    return {
        "ok": True,
        "checked_at": datetime.datetime.utcnow().isoformat(),
        "needs_google_reauth": google_needs_reauth,
        "reauth_url": _reauth_url(),
        "summary": summary,
        "services": services,
    }


@app.route("/api/ios/tokens/status")
def ios_tokens_status():
    err = _ios_auth()
    if err:
        return err
    return jsonify(_token_center_payload(force_google=False))


@app.route("/api/ios/tokens/refresh-all", methods=["POST"])
def ios_tokens_refresh_all():
    err = _ios_auth()
    if err:
        return err
    return jsonify(_token_center_payload(force_google=True))


@app.route("/api/ios/tokens/gemini", methods=["POST"])
def ios_tokens_gemini():
    err = _ios_auth()
    if err:
        return err
    payload = request.get_json(silent=True) or {}
    api_key = str(payload.get("api_key") or "").strip()
    if len(api_key) < 20:
        return jsonify({"error": "مفتاح Gemini قصير أو غير صالح."}), 400
    check = _check_gemini_key(api_key)
    if check["status"] != "ok":
        return jsonify({"error": check["message"]}), 400
    token_store.save_gemini_api_key(api_key)
    return jsonify(_token_center_payload(force_google=False))


@app.route("/api/ios/health/day")
def ios_health_day():
    """Compatibility endpoint for old app builds."""
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "summary",
            date_str,
            lambda: {
                "ok": True,
                "dashboard": _dashboard_payload(date_str),
                "sleep": _sleep_details_ios(get_sleep(date_str)),
            },
            force,
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/health/sleep")
def ios_health_sleep():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "sleep", date_str, lambda: _payload_sleep(date_str), force
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/health/heart")
def ios_health_heart():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "heart", date_str, lambda: _payload_heart(date_str), force
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/health/activity")
def ios_health_activity():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "activity", date_str, lambda: _payload_activity(date_str), force
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/health/readiness")
def ios_health_readiness():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "readiness", date_str, lambda: _payload_readiness(date_str), force
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/health/summary")
def ios_health_summary():
    err = _ios_auth()
    if err:
        return err
    try:
        date_str = request.args.get("date") or _local_today_iso()
        force = request.args.get("force") == "1"
        payload, cache_hit = _health_archive_cached(
            "summary", date_str, lambda: _payload_summary(date_str), force
        )
        return jsonify({**payload, "cache_hit": cache_hit})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/device/status")
def ios_device_status():
    err = _ios_auth()
    if err:
        return err

    force = request.args.get("force") == "1"
    payload = None if force else _cache_get("device:status", 30)

    if payload is None:
        payload = _safe_device_status_payload()
        _cache_set("device:status", payload)

    return jsonify(payload)


@app.route("/api/ios/heart/live")
def ios_heart_live():
    err = _ios_auth()
    if err:
        return err

    # Intentionally no Railway cache: always ask for the newest available reading.
    return jsonify(_safe_live_heart_payload())


@app.route("/api/ios/diagnostics")
def ios_diagnostics():
    err = _ios_auth()
    if err:
        return err

    result = {
        "ok": True,
        "railway": {
            "status": "ok",
            "message": "Railway متصل.",
        },
        "token": {
            "status": "unknown",
            "message": "لم يتم فحص التوكن بعد.",
        },
        "device": {
            "status": "unknown",
            "message": "لم يتم فحص حالة السوار بعد.",
        },
        "heart": {
            "status": "unknown",
            "message": "لم يتم فحص النبض بعد.",
            "bpm": None,
            "measured_at": None,
            "age_seconds": None,
        },
        "checked_at": datetime.datetime.utcnow().isoformat(),
    }

    try:
        get_access_token()
        result["token"] = {
            "status": "ok",
            "message": "توكن Google Health صالح.",
        }
    except TokenExpiredError:
        result["token"] = {
            "status": "reauth",
            "message": "التوكن يحتاج تجديد الربط.",
        }
    except Exception:
        result["token"] = {
            "status": "unavailable",
            "message": "تعذر التحقق من التوكن.",
        }

    device = _safe_device_status_payload()
    result["device"] = {
        "status": device["status"],
        "message": device["message"],
        "battery_level": device["battery_level"],
        "last_sync_time": device["last_sync_time"],
    }

    heart = _safe_live_heart_payload()
    result["heart"] = {
        "status": heart["status"],
        "message": heart["message"],
        "bpm": heart["bpm"],
        "measured_at": heart["measured_at"],
        "age_seconds": heart["age_seconds"],
    }

    return jsonify(result)




@app.route("/api/ios/body")
def ios_body_summary():
    err = _ios_auth()
    if err: return err
    return jsonify({"ok": True, **wellness_tracker.extended_body_summary()})

@app.route("/api/ios/body/weight", methods=["POST"])
def ios_body_weight():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        gym_tracker.add_body_weight(float(x.get("weight")))
        return jsonify({"ok": True, **wellness_tracker.extended_body_summary()})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/ios/body/weight/delete", methods=["POST", "DELETE"])
def ios_body_weight_delete():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        entry_id = int(x.get("id"))
        if not gym_tracker.delete_body_weight(entry_id):
            return jsonify({"error": "تسجيل الوزن غير موجود"}), 404
        return jsonify({"ok": True, **wellness_tracker.extended_body_summary()})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/body/profile", methods=["POST"])
def ios_body_profile():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        target = float(x["target_weight"]) if x.get("target_weight") not in (None, "") else None
        calories = int(x["daily_calories"]) if x.get("daily_calories") not in (None, "") else None
        protein = int(x["protein_grams"]) if x.get("protein_grams") not in (None, "") else None
        carbs = int(x["carb_grams"]) if x.get("carb_grams") not in (None, "") else None
        fat = int(x["fat_grams"]) if x.get("fat_grams") not in (None, "") else None
        if target is not None and not 25 <= target <= 350: raise ValueError("الهدف غير صالح")
        if calories is not None and not 500 <= calories <= 10000: raise ValueError("السعرات غير صالحة")
        if protein is not None and not 0 <= protein <= 500: raise ValueError("البروتين غير صالح")
        if carbs is not None and not 0 <= carbs <= 1200: raise ValueError("الكارب غير صالح")
        if fat is not None and not 0 <= fat <= 500: raise ValueError("الدهون غير صالحة")
        wellness_tracker.save_profile_macros(target, calories, protein, carbs, fat)
        return jsonify({"ok": True, **wellness_tracker.extended_body_summary()})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/ios/plan")
def ios_plan():
    err = _ios_auth()
    if err: return err
    plan = gym_tracker.get_workout_plan()
    return jsonify({"ok": True, "days": [{"key": k, "label": v["label"], "exercises": v["exercises"]} for k,v in plan.items()]})

@app.route("/api/ios/workout/context")
def ios_workout_context():
    err = _ios_auth()
    if err: return err
    day_key = request.args.get("day"); idx = request.args.get("idx")
    day, exercise = _resolve_exercise(day_key, idx)
    if not exercise: return jsonify({"error": "التمرين غير موجود"}), 400
    owner = str(ALLOWED_CHAT_ID or "ios-owner")
    gym_tracker.start_exercise(owner, day_key, exercise)
    last = gym_tracker.get_last_session(day_key, exercise)
    if last:
        last["sets"] = wellness_tracker.decorate_sets(last.get("sets", []))
    rec = recommend_next_weight(day_key, exercise)
    return jsonify({"ok": True, "day_label": day["label"], "exercise": exercise,
                    "today_sets": wellness_tracker.decorate_sets(gym_tracker.get_today_sets(day_key, exercise)),
                    "last_session": last, "recommendation": rec})

@app.route("/api/ios/workout/set", methods=["POST"])
def ios_workout_set():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    day_key, idx = x.get("day"), x.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    if not exercise: return jsonify({"error": "التمرين غير موجود"}), 400
    try:
        reps, weight = int(x.get("reps")), float(x.get("weight"))
        if not (1 <= reps <= 999 and 0 <= weight <= 1000): raise ValueError
    except Exception: return jsonify({"error": "تأكد من الوزن والعدات"}), 400
    owner = str(ALLOWED_CHAT_ID or "ios-owner")
    saved = gym_tracker.record_set_direct(day_key, exercise, reps, weight)
    set_number = saved["set_number"]
    wellness_tracker.save_set_feedback(saved["id"], x.get("rpe"), bool(x.get("pain")), x.get("note") or "")
    events = detect_pr(day_key, exercise, reps, weight, set_number=set_number)
    for event in events:
        gym_tracker.save_pr(owner, day_key, exercise, event)
    _invalidate_ios_cache()
    return jsonify({
        "ok": True,
        "saved_set": set_number,
        "today_sets": wellness_tracker.decorate_sets(gym_tracker.get_today_sets(day_key, exercise)),
        "pr_events": events,
    })

@app.route("/api/ios/workout/edit", methods=["POST"])
def ios_workout_edit():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    day_key, idx = x.get("day"), x.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    try:
        reps, weight = int(x["reps"]), float(x["weight"])
        set_id = int(x["id"]) if x.get("id") is not None else None
        set_number = int(x["set_number"]) if x.get("set_number") is not None else None
    except Exception:
        return jsonify({"error":"بيانات غير صالحة"}), 400

    if not exercise:
        return jsonify({"error":"التمرين غير موجود"}), 404

    updated = (
        gym_tracker.update_set_by_id(set_id, reps, weight)
        if set_id is not None
        else gym_tracker.update_set(day_key, exercise, set_number, reps, weight)
    )
    if not updated:
        return jsonify({"error":"لم أجد الجولة"}), 404
    if set_id is not None and any(key in x for key in ("rpe", "pain", "note")):
        wellness_tracker.save_set_feedback(set_id, x.get("rpe"), bool(x.get("pain")), x.get("note") or "")
    _invalidate_ios_cache()
    return jsonify({"ok": True, "today_sets": wellness_tracker.decorate_sets(gym_tracker.get_today_sets(day_key, exercise))})

@app.route("/api/ios/exercise/add", methods=["POST"])
def ios_exercise_add():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try: gym_tracker.add_exercise(x.get("day"), x.get("name")); return jsonify({"ok":True})
    except Exception as e: return jsonify({"error":str(e)}), 400

@app.route("/api/ios/exercise/delete", methods=["POST"])
def ios_exercise_delete():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    return jsonify({"ok": bool(gym_tracker.delete_exercise(x.get("day"), x.get("name")))})

@app.route("/api/ios/exercise/rename", methods=["POST"])
def ios_exercise_rename():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        gym_tracker.rename_exercise(x.get("day"), x.get("old_name"), x.get("new_name"))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route("/api/ios/exercise/reorder", methods=["POST"])
def ios_exercise_reorder():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        gym_tracker.reorder_exercises(x.get("day"), x.get("exercises") or [])
        _invalidate_ios_cache()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route("/api/ios/exercise/move", methods=["POST"])
def ios_exercise_move():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        gym_tracker.move_exercise(x.get("source_day"), x.get("target_day"), x.get("name"))
        _invalidate_ios_cache()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/ios/section/add", methods=["POST"])
def ios_section_add():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        key = gym_tracker.add_section(x.get("label"))
        return jsonify({"ok": True, "key": key})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/ios/section/rename", methods=["POST"])
def ios_section_rename():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try:
        gym_tracker.rename_section(x.get("day"), x.get("label"))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/ios/section/delete", methods=["POST"])
def ios_section_delete():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    return jsonify({"ok": bool(gym_tracker.delete_section(x.get("day")))})

@app.route("/api/ios/history")
def ios_history():
    err = _ios_auth()
    if err: return err
    try: limit = max(1, min(int(request.args.get("limit", 365)), 365))
    except Exception: limit = 365
    records = gym_tracker.get_history_records(limit_dates=limit)
    labels = {k:v.get("label",k) for k,v in gym_tracker.get_workout_plan().items()}
    for d in records:
        for ex in d["exercises"]: ex["day_label"] = labels.get(ex["day_key"], ex["day_key"])
    return jsonify({"ok":True, "records":records})

@app.route("/api/ios/history/edit", methods=["POST"])
def ios_history_edit():
    err = _ios_auth()
    if err:
        return err
    x = request.get_json(silent=True) or {}
    try:
        ok = gym_tracker.update_history_set(int(x["id"]), int(x["reps"]), float(x["weight"]))
    except Exception:
        return jsonify({"error":"بيانات غير صالحة"}), 400

    if ok:
        owner = str(ALLOWED_CHAT_ID or "ios-owner")
        gym_tracker.rebuild_analytics(owner)
        _invalidate_ios_cache()

    return jsonify({"ok":bool(ok)}), (200 if ok else 404)

@app.route("/api/ios/history/delete", methods=["POST"])
def ios_history_delete():
    err = _ios_auth()
    if err:
        return err
    x = request.get_json(silent=True) or {}
    try:
        ok = gym_tracker.delete_history_set(int(x["id"]))
    except Exception:
        ok = False

    if ok:
        owner = str(ALLOWED_CHAT_ID or "ios-owner")
        gym_tracker.rebuild_analytics(owner)
        _invalidate_ios_cache()

    return jsonify({"ok":bool(ok)}), (200 if ok else 404)

@app.route("/api/ios/analytics/rebuild", methods=["POST"])
def ios_analytics_rebuild():
    err = _ios_auth()
    if err:
        return err
    owner = str(ALLOWED_CHAT_ID or "ios-owner")
    try:
        result = gym_tracker.rebuild_analytics(owner)
        _invalidate_ios_cache()
        return jsonify({
            "ok": True,
            "message": "تمت إعادة بناء التحليلات والأرقام الشخصية من السجل الحالي.",
            "sets_scanned": result["sets_scanned"],
            "prs_created": result["prs_created"],
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ios/coach", methods=["POST"])
def ios_coach():
    err = _ios_auth()
    if err:
        return err

    x = request.get_json(silent=True) or {}
    q = (x.get("message") or "").strip()
    if not q:
        return jsonify({"error": "اكتب سؤالك"}), 400

    owner = str(ALLOWED_CHAT_ID or "ios-owner")

    try:
        today = get_today_summary()
        week = get_week_summary()

        # Conversation memory only.
        hist = gym_tracker.get_history(owner, limit=16)

        # Fresh DB context on EVERY message:
        # current plan + added exercises + deleted/inactive historical exercises
        # + recent detailed sets + progress + load + PRs.
        personal_context = gym_tracker.build_full_coach_context(
            question=q,
            recent_dates=14,
        )

        readiness_context = coach_context(today)
        full_context = (
            readiness_context
            + "\n\n"
            + personal_context
            + "\n\n"
            + wellness_tracker.coach_context()
            + "\n\n"
            + activity_tracker.coach_context()
        ).strip()

        answer = ask_coach(
            q,
            week,
            today,
            gym_context=full_context,
            history=hist,
        )

        gym_tracker.save_message(owner, "user", q)
        gym_tracker.save_message(owner, "model", answer)
        return jsonify({"ok": True, "answer": answer})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/ios/insights")
def ios_insights():
    err = _ios_auth()
    if err:
        return err
    try:
        force = request.args.get("force") == "1"
        key = "insights:latest"
        payload = None if force else _cache_get(key, 300)

        if payload is None:
            started = time.monotonic()
            today = get_today_summary()
            payload = {
                "ok": True,
                "readiness": format_readiness(today),
                "today_plan": today_plan(today),
                "progress": progress_report(),
                "balance": format_muscle_balance(),
                "next_weights": format_next_suggestions(),
                "weekly_report": weekly_report(today),
                "updated_at": datetime.datetime.utcnow().isoformat(),
                "server_ms": int((time.monotonic() - started) * 1000),
            }
            _cache_set(key, payload)

        return jsonify(payload)
    except Exception as e:
        return jsonify({"error":str(e)}), 500

# ---------------------------------------------------------------------------
# FitbitAir 2.0 — nutrition, body progress, reports, and workout intelligence
# ---------------------------------------------------------------------------

def _decode_ios_image(value, max_bytes=7_000_000):
    raw = str(value or "")
    if raw.startswith("data:") and "," in raw:
        raw = raw.split(",", 1)[1]
    try:
        data = base64.b64decode(raw, validate=True)
    except Exception as exc:
        raise ValueError("الصورة غير صالحة") from exc
    if not data or len(data) > max_bytes:
        raise ValueError("حجم الصورة غير صالح")
    return data


def _nutrition_image_prompt(mode):
    if mode == "meal":
        return """حلل صورة الوجبة كتقدير فقط. أرجع JSON فقط بهذا الشكل:
{
  "name": "اسم مختصر للوجبة",
  "serving_grams": 100,
  "calories_per_100": 0,
  "protein_per_100": 0,
  "carbs_per_100": 0,
  "fat_per_100": 0,
  "estimated_total_grams": 0,
  "estimated_total_calories": 0,
  "items": [{"name":"","estimated_grams":0,"calories":0,"protein":0,"carbs":0,"fat":0}],
  "confidence": "منخفض|متوسط|مرتفع",
  "notes": "وضح أن التقدير يتأثر بالحجم والزيت وطريقة الطبخ"
}
اجعل القيم الغذائية per_100 محسوبة لكل 100غ من مجموع الوجبة، ولا تدّعي الدقة الطبية. لا تتعرف على هوية أي شخص إن ظهر في الصورة."""
    return """اقرأ جدول القيم الغذائية وواجهة العبوة من الصورة. أرجع JSON فقط بهذا الشكل:
{
  "name": "اسم المنتج",
  "brand": "العلامة إن ظهرت",
  "serving_grams": 0,
  "calories_per_100": 0,
  "protein_per_100": 0,
  "carbs_per_100": 0,
  "fat_per_100": 0,
  "confidence": "منخفض|متوسط|مرتفع",
  "notes": "أي ملاحظة عن القيم أو الحصة"
}
حوّل القيم إلى لكل 100غ إن كانت العبوة تعرضها للحصة فقط. إذا رقم غير واضح اجعله 0 واذكر ذلك في notes. لا تخمّن اسم منتج غير ظاهر."""


@app.route("/api/ios/nutrition/day")
def ios_nutrition_day():
    err = _ios_auth()
    if err: return err
    date = request.args.get("date") or wellness_tracker.qatar_today()
    return jsonify({"ok": True, **wellness_tracker.nutrition_day(date)})


@app.route("/api/ios/nutrition/range")
def ios_nutrition_range():
    err = _ios_auth()
    if err: return err
    try:
        days = int(request.args.get("days", 7))
    except Exception:
        days = 7
    return jsonify({"ok": True, **wellness_tracker.nutrition_range(days)})


@app.route("/api/ios/nutrition/log", methods=["POST"])
def ios_nutrition_log():
    err = _ios_auth()
    if err: return err
    try:
        payload = request.get_json(silent=True) or {}
        result = wellness_tracker.log_food(payload)
        return jsonify({"ok": True, **result})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/nutrition/log/delete", methods=["POST", "DELETE"])
def ios_nutrition_log_delete():
    err = _ios_auth()
    if err:
        return err

    payload = request.get_json(silent=True) or {}
    raw_id = payload.get("id") or request.args.get("id")
    try:
        log_date = wellness_tracker.delete_food(int(raw_id))
    except Exception as exc:
        return jsonify({"ok": False, "error": f"تعذر حذف العنصر: {exc}"}), 400

    if not log_date:
        return jsonify({"ok": False, "error": "العنصر غير موجود أو تم حذفه مسبقًا."}), 404

    return jsonify({"ok": True, **wellness_tracker.nutrition_day(log_date)})


@app.route("/api/ios/nutrition/products")
def ios_nutrition_products():
    err = _ios_auth()
    if err: return err
    query = request.args.get("q", "")
    favorites = request.args.get("favorites") == "1"
    return jsonify({"ok": True, "products": wellness_tracker.list_products(query, favorites)})


@app.route("/api/ios/nutrition/product/barcode")
def ios_nutrition_barcode():
    err = _ios_auth()
    if err: return err
    try:
        result = wellness_tracker.lookup_barcode(request.args.get("code", ""))
        return jsonify({"ok": True, **result})
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    except Exception as exc:
        return jsonify({"error": str(exc)}), 502


@app.route("/api/ios/nutrition/product/favorite", methods=["POST"])
def ios_nutrition_favorite():
    err = _ios_auth()
    if err: return err
    payload = request.get_json(silent=True) or {}
    try:
        product = wellness_tracker.toggle_favorite(int(payload.get("id")), bool(payload.get("favorite")))
        return jsonify({"ok": True, "product": product})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/nutrition/analyze-image", methods=["POST"])
def ios_nutrition_analyze_image():
    err = _ios_auth()
    if err: return err
    payload = request.get_json(silent=True) or {}
    mode = "meal" if payload.get("mode") == "meal" else "label"
    try:
        image = _decode_ios_image(payload.get("image_base64"))
        result = analyze_images_json(
            _nutrition_image_prompt(mode),
            [(image, payload.get("mime_type") or "image/jpeg")],
            max_tokens=1900,
            temperature=0.12,
        )
        if not isinstance(result, dict):
            raise ValueError("تعذر فهم نتيجة الصورة")
        # Normalize numeric values to make the iOS contract stable.
        for key in ("serving_grams", "calories_per_100", "protein_per_100", "carbs_per_100", "fat_per_100", "estimated_total_grams", "estimated_total_calories"):
            if key in result:
                try: result[key] = max(0, float(result.get(key) or 0))
                except Exception: result[key] = 0
        result["source"] = "gemini_" + mode
        result["mode"] = mode
        return jsonify({"ok": True, "analysis": result})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/body/progress")
def ios_body_progress():
    err = _ios_auth()
    if err: return err
    return jsonify({"ok": True, **wellness_tracker.body_progress()})


@app.route("/api/ios/body/measurement", methods=["POST"])
def ios_body_measurement():
    err = _ios_auth()
    if err: return err
    try:
        result = wellness_tracker.save_measurement(request.get_json(silent=True) or {})
        return jsonify({"ok": True, **result})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/body/analyze", methods=["POST"])
def ios_body_analyze():
    err = _ios_auth()
    if err: return err
    payload = request.get_json(silent=True) or {}
    try:
        baseline = _decode_ios_image(payload.get("baseline_image_base64"))
        current = _decode_ios_image(payload.get("current_image_base64"))
        pose = payload.get("pose") or "front"
        prompt = f"""قارن صورتي تقدم جسم لنفس الشخص في وضعية {pose}. الصورة الأولى أقدم والثانية أحدث.
أرجع JSON فقط:
{{
  "summary": "ملخص عربي مباشر ومحترم للتغيرات المرئية",
  "visible_changes": ["تغير مرئي 1", "تغير مرئي 2"],
  "areas_improved": ["مناطق ظهر فيها تحسن إن وجد"],
  "areas_to_focus": ["مناطق تدريب مقترحة بدون انتقاد جارح"],
  "confidence": "منخفض|متوسط|مرتفع",
  "photo_consistency": "مدى تشابه الإضاءة والزاوية",
  "estimated_body_fat_range": "نطاق تقريبي واسع أو غير متاح"
}}
قواعد: لا تتعرف على هوية الشخص، لا تشخص مرضًا، لا تعط نسبة دهون دقيقة، واذكر إذا اختلاف الإضاءة أو الوقفة يمنع المقارنة. ركز على المقارنة وليس الحكم على الشكل."""
        result = analyze_images_json(prompt, [(baseline, "image/jpeg"), (current, "image/jpeg")], max_tokens=1800, temperature=0.15)
        if not isinstance(result, dict):
            raise ValueError("تعذر فهم نتيجة المقارنة")
        saved = wellness_tracker.save_body_analysis({
            **result,
            "baseline_date": payload.get("baseline_date"),
            "current_date": payload.get("current_date"),
            "pose": pose,
        })
        return jsonify({"ok": True, "analysis": {**result, **saved}})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/workout/session", methods=["POST"])
def ios_workout_session():
    err = _ios_auth()
    if err: return err
    try:
        return jsonify({"ok": True, "session": wellness_tracker.log_session(request.get_json(silent=True) or {})})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/ios/workout/alternatives")
def ios_workout_alternatives():
    err = _ios_auth()
    if err: return err
    exercise = " ".join((request.args.get("exercise") or "").split())
    if len(exercise) < 2:
        return jsonify({"error": "اسم التمرين مطلوب"}), 400
    cached = wellness_tracker.cached_alternatives(exercise)
    if cached:
        return jsonify({"ok": True, "exercise": exercise, "alternatives": cached, "cached": True})
    try:
        result = generate_structured_json(
            f'''أنت مدرب مقاومة. أعط بدائل آمنة وعملية للتمرين التالي: {exercise}.
أرجع JSON فقط: {{"alternatives":["اسم البديل — سبب قصير","..."]}}.
اختر 5 بدائل تغطي جهاز، دامبل، كيبل أو وزن جسم إن أمكن. لا تقدم بديلًا مؤلمًا أو تشخيصًا طبيًا.''',
            max_tokens=850,
            temperature=0.22,
        )
        alternatives = result.get("alternatives", []) if isinstance(result, dict) else []
        alternatives = wellness_tracker.save_alternatives(exercise, alternatives)
        return jsonify({"ok": True, "exercise": exercise, "alternatives": alternatives, "cached": False})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


def _daily_report_fallback(dashboard, nutrition, body):
    sleep = dashboard.get("sleep_minutes")
    rest = dashboard.get("resting_hr")
    steps = dashboard.get("steps")
    totals = nutrition.get("totals", {})
    parts = []
    if sleep is not None: parts.append(f"نمت {sleep // 60}س و{sleep % 60}د")
    if rest is not None: parts.append(f"نبض الراحة {rest}")
    if steps is not None: parts.append(f"خطواتك {steps}")
    if totals.get("protein"): parts.append(f"سجلت {totals['protein']:g}غ بروتين")
    summary = "، ".join(parts) if parts else "بيانات اليوم ما زالت محدودة؛ حدّث المزامنة وسجل أكلك للحصول على تقرير أدق."
    return {"summary": summary + ".", "details": dashboard.get("today_plan") or "استمر على خطتك الحالية."}


def _make_report(report_type, force=False):
    today_date = wellness_tracker.qatar_today()
    report_date = today_date if report_type == "daily" else f"{today_date}-week"
    if not force:
        cached = wellness_tracker.get_report(report_type, report_date)
        if cached:
            return {
                "report_type": report_type,
                "date": report_date,
                "summary": cached["summary"],
                "details": cached.get("details") or "",
                "created_at": cached.get("created_at"),
                "cached": True,
            }

    if report_type == "daily":
        dashboard = _dashboard_payload(today_date)
        nutrition = wellness_tracker.nutrition_day(today_date)
        body = wellness_tracker.body_progress(12)
        workout = gym_tracker.get_day_summary(datetime.datetime.utcnow().date().isoformat())
        prompt = f'''اكتب تقرير أحمد اليومي بالعربية الخليجية الواضحة باستخدام البيانات الفعلية فقط.
بيانات الصحة: {json.dumps(dashboard, ensure_ascii=False)}
التغذية: {json.dumps(nutrition, ensure_ascii=False)}
قياسات الجسم: {json.dumps(body.get("latest"), ensure_ascii=False)}
تمرين اليوم: {json.dumps(workout, ensure_ascii=False)}
النشاطات الهوائية والرياضية: {activity_tracker.coach_context(days=3)}
أرجع JSON فقط: {{"summary":"فقرة قصيرة جدًا","details":"4 نقاط عملية مرقمة كنص واحد","readiness_label":"","nutrition_note":"","training_note":""}}.
لا تخترع بيانات، وإذا شيء ناقص قل إنه غير مسجل.'''
        try:
            result = generate_structured_json(prompt, max_tokens=1300, temperature=0.2)
            summary = str(result.get("summary") or "").strip()
            detail_parts = [result.get("details"), result.get("nutrition_note"), result.get("training_note")]
            details = "\n".join(str(x).strip() for x in detail_parts if x)
            if not summary: raise ValueError
        except Exception:
            fallback = _daily_report_fallback(dashboard, nutrition, body)
            summary, details = fallback["summary"], fallback["details"]
    else:
        nutrition = wellness_tracker.nutrition_range(7)
        body = wellness_tracker.body_progress(30)
        workout_context = gym_tracker.build_full_coach_context(question="تقرير أسبوعي", recent_dates=7)
        wellness_context = wellness_tracker.coach_context()
        prompt = f'''أنشئ تقرير أسبوعي احترافي لأحمد مبنيًا على البيانات التالية فقط:
التغذية: {json.dumps(nutrition, ensure_ascii=False)}
الجسم: {json.dumps(body, ensure_ascii=False)}
التمارين: {workout_context}
مؤشرات RPE والألم والجلسات: {wellness_context}
النشاطات الهوائية والرياضية: {activity_tracker.coach_context(days=7)}
أرجع JSON فقط: {{"summary":"ملخص أسبوعي قصير","details":"الإنجازات ثم الملاحظات ثم 3 أهداف للأسبوع القادم"}}.
لا تخترع أرقامًا ولا تقدم تشخيصًا طبيًا.'''
        try:
            result = generate_structured_json(prompt, max_tokens=1700, temperature=0.24)
            summary = str(result.get("summary") or "").strip()
            details = str(result.get("details") or "").strip()
            if not summary: raise ValueError
        except Exception:
            summary = f"سجلت الأكل في {nutrition['logged_days']} أيام خلال الأسبوع."
            details = "افتح سجل التمارين والتغذية وأكمل الأيام الناقصة للحصول على تحليل أسبوعي أدق."
    saved = wellness_tracker.save_report(report_type, report_date, summary, details)
    return {**saved, "cached": False}



# ---------------------------------------------------------------------------
# FitbitAir activity sessions
# ---------------------------------------------------------------------------

def _activity_google_payload(session):
    return {
        "client_id": session.get("client_id"),
        "exercise_type": session.get("exercise_type"),
        "display_name": session.get("display_name"),
        "start_time": session.get("start_time"),
        "end_time": session.get("end_time"),
        "duration_seconds": session.get("duration_seconds"),
        "active_seconds": session.get("active_seconds"),
        "distance_meters": session.get("distance_meters"),
        "calories": session.get("calories"),
        "steps": session.get("steps"),
        "average_heart_rate": session.get("average_heart_rate"),
        "average_speed_mps": session.get("average_speed_mps"),
        "elevation_gain_meters": session.get("elevation_gain_meters"),
        "active_zone_minutes": session.get("active_zone_minutes"),
        "has_gps": session.get("has_gps"),
        "notes": session.get("notes"),
        "utc_offset_seconds": 10800,
    }


def _operation_name(operation):
    if not isinstance(operation, dict):
        return None
    return operation.get("name") or (operation.get("response") or {}).get("name")


@app.route("/api/ios/activities")
def ios_activities_list():
    err = _ios_auth()
    if err: return err
    try:
        days = max(1, min(365, int(request.args.get("days", 30))))
        return jsonify({
            "ok": True,
            "sessions": activity_tracker.list_sessions(days=days),
            "summary": activity_tracker.summary(days=min(days, 30)),
            "reauth_url": _reauth_url(),
        })
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/ios/activities/session", methods=["POST"])
def ios_activity_session_save():
    err = _ios_auth()
    if err: return err
    payload = request.get_json(silent=True) or {}
    try:
        session = activity_tracker.save_local_session(payload)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    # Idempotency: if the iPhone retries after a slow/lost response, do not create
    # the same Google Health exercise twice.
    if session.get("sync_status") in {"uploaded", "synced"}:
        return jsonify({
            "ok": True,
            "session": session,
            "google_status": session.get("sync_status"),
            "message": "النشاط محفوظ ومتزامن مسبقًا",
            "needs_reauth": False,
            "reauth_url": None,
        })

    google_status = "local_only"
    google_message = "تم الحفظ داخل FitbitAir"
    needs_reauth = False
    try:
        operation = create_exercise_session(_activity_google_payload(session))
        session = activity_tracker.mark_google_sync(session["id"], "uploaded", _operation_name(operation))
        google_status = "uploaded"
        google_message = "تم الحفظ وإرساله إلى Google Health"
    except TokenExpiredError as exc:
        session = activity_tracker.mark_google_sync(session["id"], "needs_reauth", error=exc)
        google_status = "needs_reauth"
        google_message = "تم الحفظ داخل التطبيق ويحتاج تحديث صلاحيات Google"
        needs_reauth = True
    except GoogleHealthError as exc:
        text = str(exc)
        needs_reauth = any(code in text for code in ("401", "403", "PERMISSION_DENIED", "insufficient"))
        status = "needs_reauth" if needs_reauth else "pending"
        session = activity_tracker.mark_google_sync(session["id"], status, error=text)
        google_status = status
        google_message = "تم الحفظ محليًا وسيعاد إرسال النشاط بعد المزامنة"
    _invalidate_ios_cache()
    return jsonify({
        "ok": True,
        "session": session,
        "google_status": google_status,
        "message": google_message,
        "needs_reauth": needs_reauth,
        "reauth_url": _reauth_url() if needs_reauth else None,
    })


@app.route("/api/ios/activities/session/delete", methods=["POST", "DELETE"])
def ios_activity_session_delete():
    err = _ios_auth()
    if err: return err
    data = request.get_json(silent=True) or {}
    try:
        session_id = int(data.get("id"))
    except Exception:
        return jsonify({"error": "معرّف النشاط غير صالح"}), 400
    try:
        deleted = activity_tracker.delete_session(session_id)
        if not deleted:
            return jsonify({"error": "النشاط غير موجود"}), 404
        _invalidate_ios_cache()
        days = max(1, min(365, int(data.get("days", 30))))
        return jsonify({
            "ok": True,
            "sessions": activity_tracker.list_sessions(days=days),
            "summary": activity_tracker.summary(days=min(days, 30)),
            "reauth_url": _reauth_url(),
        })
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/ios/activities/sync", methods=["POST"])
def ios_activities_sync():
    err = _ios_auth()
    if err: return err
    data = request.get_json(silent=True) or {}
    try:
        days = max(1, min(90, int(data.get("days", 30))))
        end = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1)
        start = end - datetime.timedelta(days=days)
        points = list_exercises(
            start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            end.strftime("%Y-%m-%dT%H:%M:%SZ"),
            reconcile=True,
        )
        result = activity_tracker.import_google_exercises(points)

        # Retry local sessions that were not uploaded yet after permissions change.
        uploaded = 0
        for session in activity_tracker.list_sessions(days=days, limit=200):
            if session.get("source") == "google_health" or session.get("sync_status") in {"synced", "uploaded"}:
                continue
            try:
                operation = create_exercise_session(_activity_google_payload(session))
                activity_tracker.mark_google_sync(session["id"], "uploaded", _operation_name(operation))
                uploaded += 1
            except Exception:
                pass
        _invalidate_ios_cache()
        return jsonify({
            "ok": True,
            "imported": result["imported"],
            "merged": result["merged"],
            "uploaded": uploaded,
            "sessions": activity_tracker.list_sessions(days=days),
            "summary": activity_tracker.summary(days=min(days, 30)),
            "message": "اكتملت مزامنة النشاطات",
        })
    except TokenExpiredError as exc:
        return jsonify({"error": str(exc), "needs_reauth": True, "reauth_url": _reauth_url()}), 401
    except GoogleHealthError as exc:
        text = str(exc)
        needs_reauth = any(code in text for code in ("401", "403", "PERMISSION_DENIED", "insufficient"))
        return jsonify({"error": text, "needs_reauth": needs_reauth, "reauth_url": _reauth_url() if needs_reauth else None}), (403 if needs_reauth else 502)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/ios/activities/summary")
def ios_activities_summary():
    err = _ios_auth()
    if err: return err
    try:
        days = max(1, min(365, int(request.args.get("days", 7))))
        return jsonify({"ok": True, "summary": activity_tracker.summary(days)})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

@app.route("/api/ios/reports/daily")
def ios_daily_report():
    err = _ios_auth()
    if err: return err
    try:
        return jsonify({"ok": True, "report": _make_report("daily", request.args.get("force") == "1")})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/ios/reports/weekly")
def ios_weekly_wellness_report():
    err = _ios_auth()
    if err: return err
    try:
        return jsonify({"ok": True, "report": _make_report("weekly", request.args.get("force") == "1")})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

if __name__ == "__main__":
    app.run()
