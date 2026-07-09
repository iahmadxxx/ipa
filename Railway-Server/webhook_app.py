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
import hmac
import time
from urllib.parse import parse_qsl

import requests
from flask import Flask, request, jsonify, Response

from google_health_client import (
    get_today_summary, get_week_summary, get_sleep, get_resting_heart_rate,
    get_current_heart_rate, get_summary_by_date, get_week_summary_for, GoogleHealthError,
    TokenExpiredError,
)
import token_store
from analyzer import (
    format_today_message, format_week_message, format_sleep_message,
    format_heart_message, format_activity_message,
)
from ai_coach import analyze_week, ask_coach, transcribe_audio, AICoachError
import gym_tracker
from performance_intelligence import (
    format_readiness, today_plan, progress_report, format_muscle_balance,
    format_next_suggestions, weekly_report, recommend_next_weight,
    detect_pr, coach_context,
)

app = Flask(__name__)
gym_tracker.init_db()

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
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly "
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly"
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
    if err: return err
    try: return jsonify({"ok": True, "dashboard": _dashboard_payload(request.args.get("date"))})
    except Exception as e: return jsonify({"error": str(e)}), 500

@app.route("/api/ios/week")
def ios_week():
    err = _ios_auth()
    if err: return err
    try: return jsonify({"ok": True, "days": get_week_summary_for(request.args.get("end"))})
    except Exception as e: return jsonify({"error": str(e)}), 500

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
    rec = recommend_next_weight(day_key, exercise)
    return jsonify({"ok": True, "day_label": day["label"], "exercise": exercise,
                    "today_sets": gym_tracker.get_today_sets(day_key, exercise),
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
    pending = gym_tracker.get_pending(owner)
    if not pending or pending["day_key"] != day_key or pending["exercise"] != exercise:
        gym_tracker.start_exercise(owner, day_key, exercise)
    set_number = gym_tracker.record_set(owner, reps, weight)
    events = detect_pr(day_key, exercise, reps, weight, set_number=set_number)
    for event in events: gym_tracker.save_pr(owner, day_key, exercise, event)
    return jsonify({"ok": True, "saved_set": set_number, "today_sets": gym_tracker.get_today_sets(day_key, exercise), "pr_events": events})

@app.route("/api/ios/workout/edit", methods=["POST"])
def ios_workout_edit():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    day_key, idx = x.get("day"), x.get("idx")
    _, exercise = _resolve_exercise(day_key, idx)
    try: set_number, reps, weight = int(x["set_number"]), int(x["reps"]), float(x["weight"])
    except Exception: return jsonify({"error":"بيانات غير صالحة"}), 400
    if not exercise or not gym_tracker.update_set(day_key, exercise, set_number, reps, weight):
        return jsonify({"error":"لم أجد الجولة"}), 404
    return jsonify({"ok": True, "today_sets": gym_tracker.get_today_sets(day_key, exercise)})

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
    if err: return err
    x = request.get_json(silent=True) or {}
    try: ok = gym_tracker.update_history_set(int(x["id"]), int(x["reps"]), float(x["weight"]))
    except Exception: return jsonify({"error":"بيانات غير صالحة"}), 400
    return jsonify({"ok":bool(ok)}), (200 if ok else 404)

@app.route("/api/ios/history/delete", methods=["POST"])
def ios_history_delete():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}
    try: ok = gym_tracker.delete_history_set(int(x["id"]))
    except Exception: ok = False
    return jsonify({"ok":bool(ok)}), (200 if ok else 404)

@app.route("/api/ios/coach", methods=["POST"])
def ios_coach():
    err = _ios_auth()
    if err: return err
    x = request.get_json(silent=True) or {}; q = (x.get("message") or "").strip()
    if not q: return jsonify({"error":"اكتب سؤالك"}), 400
    owner = str(ALLOWED_CHAT_ID or "ios-owner")
    try:
        today = get_today_summary(); week = get_week_summary()
        hist = gym_tracker.get_history(owner, limit=12)
        context = coach_context(today)
        answer = ask_coach(q, week, today, gym_context=context, history=hist)
        gym_tracker.save_message(owner, "user", q); gym_tracker.save_message(owner, "model", answer)
        return jsonify({"ok":True, "answer":answer})
    except Exception as e: return jsonify({"error":str(e)}), 500

@app.route("/api/ios/insights")
def ios_insights():
    err = _ios_auth()
    if err: return err
    try:
        today = get_today_summary()
        return jsonify({"ok":True, "readiness":format_readiness(today), "today_plan":today_plan(today),
                        "progress":progress_report(), "balance":format_muscle_balance(),
                        "next_weights":format_next_suggestions(), "weekly_report":weekly_report(today)})
    except Exception as e: return jsonify({"error":str(e)}), 500

if __name__ == "__main__":
    app.run()
