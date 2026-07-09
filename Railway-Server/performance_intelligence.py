"""ذكاء الأداء: الجاهزية، التقدم، الأرقام الشخصية، توازن العضلات، والتقارير."""

from __future__ import annotations

import datetime as dt
import math
from statistics import mean

import gym_tracker

LOCAL_OFFSET = dt.timedelta(hours=3)


EXERCISE_MUSCLES = {
    "d1": {"صدر": 1.0},
    "d2": {"ظهر": 1.0},
    "d3": {"أكتاف": 1.0},
    "d4": {"أرجل": 1.0},
}


def _muscle_map(day_key, exercise):
    name = (exercise or "").lower()
    if any(k in name for k in ("باي", "biceps", "curl")):
        return {"بايسبس": 1.0}
    if any(k in name for k in ("تراي", "triceps", "pushdown", "extension", "dips")):
        return {"ترايسبس": 1.0}
    if any(k in name for k in ("ترابيس", "shrug")):
        return {"ترابيس": 1.0}
    if any(k in name for k in ("سمانة", "بطات", "calf")):
        return {"سمانة": 1.0}
    if any(k in name for k in ("كتف خلفي", "rear delt")):
        return {"أكتاف خلفية": 1.0}
    if day_key == "d4":
        if any(k in name for k in ("خلفي", "curl", "lung", "طعن")):
            return {"أرجل خلفية": 1.0, "مؤخرة": 0.35}
        return {"أرجل أمامية": 1.0}
    return EXERCISE_MUSCLES.get(day_key, {"أخرى": 1.0})



def _num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _sleep_minutes(today_data):
    sleep = (today_data or {}).get("sleep") or {}
    summary = sleep.get("summary") or {}
    for key in ("minutesAsleep", "totalSleepMinutes", "sleepDurationMinutes"):
        value = _num(summary.get(key))
        if value is not None:
            return int(value)
    start = sleep.get("_local_start")
    end = sleep.get("_local_end")
    if start and end:
        return max(0, int((end - start).total_seconds() // 60))
    return None


def _fmt_hm(minutes):
    if minutes is None:
        return "غير متوفر"
    h, m = divmod(int(minutes), 60)
    return f"{h}س {m}د"


def _clamp(value, lo=0, hi=100):
    return max(lo, min(hi, value))


def save_health_snapshot(today_data):
    date_str = (today_data or {}).get("date") or dt.date.today().isoformat()
    gym_tracker.save_health_snapshot(
        date_str=date_str,
        sleep_minutes=_sleep_minutes(today_data),
        resting_hr=(today_data or {}).get("heart_rate"),
        steps=(today_data or {}).get("steps"),
        calories=(today_data or {}).get("calories"),
    )


def calculate_readiness(today_data):
    """درجة 0-100، تتعلم خط المستخدم الطبيعي من snapshots المحفوظة."""
    save_health_snapshot(today_data)
    sleep = _sleep_minutes(today_data)
    rhr = _num((today_data or {}).get("heart_rate"))
    steps = _num((today_data or {}).get("steps"))
    baselines = gym_tracker.get_health_baseline(days=30, exclude_date=(today_data or {}).get("date"))

    # النوم: 40 نقطة
    if sleep is None:
        sleep_score = 25
    elif sleep >= 480:
        sleep_score = 40
    elif sleep >= 420:
        sleep_score = 36
    elif sleep >= 360:
        sleep_score = 29
    elif sleep >= 300:
        sleep_score = 20
    else:
        sleep_score = 12

    # نبض الراحة: 25 نقطة — مقارنة شخصية عند توفر baseline
    baseline_rhr = baselines.get("resting_hr")
    baseline_count = baselines.get("resting_hr_count", 0)
    if rhr is None:
        rhr_score = 16
        rhr_note = "نبض الراحة غير متوفر"
    elif baseline_rhr is not None and baseline_count >= 3:
        delta = rhr - baseline_rhr
        if delta <= -2:
            rhr_score = 25
        elif delta <= 2:
            rhr_score = 23
        elif delta <= 5:
            rhr_score = 18
        elif delta <= 8:
            rhr_score = 12
        else:
            rhr_score = 6
        rhr_note = f"نبض الراحة {int(rhr)}، خطك الطبيعي {baseline_rhr:.0f} ({delta:+.0f})"
    else:
        rhr_score = 22 if rhr <= 75 else 17 if rhr <= 85 else 10
        rhr_note = f"نبض الراحة {int(rhr)} — أبني خطك الطبيعي مع الاستخدام"

    # الحمل التدريبي: 25 نقطة
    load7 = gym_tracker.get_training_load(days=7)
    load28 = gym_tracker.get_training_load(days=28)
    avg_week = load28["volume"] / 4 if load28["volume"] else 0
    if load7["workout_days"] == 0:
        load_score = 22
        load_note = "ما فيه تمرين حديد مسجل آخر 7 أيام"
    elif avg_week > 0 and load7["volume"] > avg_week * 1.45:
        load_score = 12
        load_note = "حملك هذا الأسبوع أعلى بكثير من المعتاد"
    elif load7["workout_days"] >= 6:
        load_score = 15
        load_note = "أيام التدريب كثيرة؛ راقب التعافي"
    else:
        load_score = 23
        load_note = "الحمل التدريبي متوازن"

    # النشاط الحالي: 10 نقاط (لا نعاقب الصباح بقسوة)
    hour = (dt.datetime.utcnow() + LOCAL_OFFSET).hour
    expected_fraction = _clamp((hour - 7) / 15, 0.05, 1.0)
    baseline_steps = baselines.get("steps") or 8000
    expected_now = baseline_steps * expected_fraction
    if steps is None:
        activity_score = 7
    elif steps >= expected_now:
        activity_score = 10
    elif steps >= expected_now * 0.65:
        activity_score = 7
    else:
        activity_score = 4

    score = int(round(_clamp(sleep_score + rhr_score + load_score + activity_score)))
    if score >= 85:
        label, intensity = "ممتازة 🔥", "قوي"
    elif score >= 70:
        label, intensity = "جيدة 👍", "متوسط إلى قوي"
    elif score >= 55:
        label, intensity = "متوسطة ⚖️", "متوسط"
    else:
        label, intensity = "منخفضة 🛌", "خفيف أو راحة"

    return {
        "score": score,
        "label": label,
        "intensity": intensity,
        "sleep_minutes": sleep,
        "sleep_score": sleep_score,
        "rhr_score": rhr_score,
        "rhr_note": rhr_note,
        "load_score": load_score,
        "load_note": load_note,
        "activity_score": activity_score,
        "baseline": baselines,
    }


def format_readiness(today_data):
    r = calculate_readiness(today_data)
    return (
        f"⚡ جاهزيتك اليوم: {r['score']}/100 — {r['label']}\n\n"
        f"😴 النوم: {_fmt_hm(r['sleep_minutes'])} ({r['sleep_score']}/40)\n"
        f"❤️ {r['rhr_note']} ({r['rhr_score']}/25)\n"
        f"🏋️ {r['load_note']} ({r['load_score']}/25)\n"
        f"🚶 النشاط الحالي ({r['activity_score']}/10)\n\n"
        f"🎯 شدة اليوم المناسبة: {r['intensity']}"
    )


def recommend_next_weight(day_key, exercise):
    history = gym_tracker.get_exercise_history(day_key, exercise, limit=4)
    if not history:
        return None
    latest = history[0]
    sets = latest["sets"]
    if not sets:
        return None
    weights = [_num(s["weight"]) for s in sets if _num(s["weight"]) is not None]
    reps = [int(s["reps"]) for s in sets if s.get("reps") is not None]
    if not weights or not reps:
        return None

    top_weight = max(weights)
    top_sets = [s for s in sets if _num(s["weight"]) == top_weight]
    avg_reps = mean(int(s["reps"]) for s in top_sets)
    step = 2.5 if top_weight >= 20 else 1.0

    if avg_reps >= 12 and len(top_sets) >= 2:
        next_weight = top_weight + step
        text = f"ارفع إلى {next_weight:g} كجم واستهدف 8–10 تكرارات"
        action = "increase"
    elif avg_reps >= 8:
        next_weight = top_weight
        text = f"ثبّت {next_weight:g} كجم وحاول تزيد مجموع التكرارات"
        action = "hold"
    else:
        next_weight = top_weight
        text = f"ثبّت {next_weight:g} كجم لين توصل 8 تكرارات نظيفة"
        action = "build"

    trend = get_exercise_trend(day_key, exercise)
    return {
        "last_date": latest["date"],
        "last_top_weight": top_weight,
        "avg_reps": avg_reps,
        "suggested_weight": next_weight,
        "text": text,
        "action": action,
        "trend": trend,
    }


def _session_metric(session):
    volume = sum((_num(s["weight"]) or 0) * int(s["reps"]) for s in session.get("sets", []))
    e1rm = 0
    for s in session.get("sets", []):
        w = _num(s["weight"]) or 0
        reps = int(s["reps"])
        e1rm = max(e1rm, w * (1 + reps / 30))
    return {"volume": volume, "e1rm": e1rm}


def get_exercise_trend(day_key, exercise):
    history = gym_tracker.get_exercise_history(day_key, exercise, limit=6)
    if len(history) < 2:
        return {"status": "new", "change_pct": 0, "text": "لسا نحتاج جلسات أكثر لقياس التقدم"}
    metrics = [_session_metric(s) for s in history]
    recent = mean(m["e1rm"] for m in metrics[:2])
    older_pool = metrics[2:5] or metrics[1:]
    older = mean(m["e1rm"] for m in older_pool)
    change = ((recent - older) / older * 100) if older else 0
    if change >= 4:
        status, text = "up", f"تقدم واضح +{change:.1f}% 📈"
    elif change <= -5:
        status, text = "down", f"تراجع {change:.1f}% 📉 — راقب النوم والتعافي"
    else:
        status, text = "flat", f"ثبات {change:+.1f}% ➖"
    return {"status": status, "change_pct": change, "text": text}


def detect_pr(day_key, exercise, reps, weight, set_number=None):
    previous = (gym_tracker.get_best_before_set(day_key, exercise, set_number)
                if set_number is not None else gym_tracker.get_previous_best(day_key, exercise, exclude_today=True))
    events = []
    weight = float(weight)
    reps = int(reps)
    e1rm = weight * (1 + reps / 30)
    if previous["max_weight"] is None or weight > previous["max_weight"]:
        events.append(f"🏆 أعلى وزن جديد: {weight:g} كجم")
    if previous["max_reps_at_weight"] is None or reps > previous["max_reps_at_weight"].get(weight, 0):
        if weight in previous["max_reps_at_weight"]:
            events.append(f"🔥 أفضل تكرارات على {weight:g} كجم: {reps}")
    if previous["best_e1rm"] is None or e1rm > previous["best_e1rm"] * 1.005:
        events.append(f"💥 قوة تقديرية جديدة: {e1rm:.1f} كجم")
    return events[:2]


def muscle_balance(days=7):
    rows = gym_tracker.get_sets_since(days)
    scores = {}
    direct_sets = {}
    for row in rows:
        mapping = _muscle_map(row["day_key"], row.get("exercise"))
        for muscle, factor in mapping.items():
            scores[muscle] = scores.get(muscle, 0) + factor
            if factor >= 1:
                direct_sets[muscle] = direct_sets.get(muscle, 0) + 1
    ordered = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    return {"scores": ordered, "direct_sets": direct_sets, "total_sets": len(rows)}


def format_muscle_balance(days=7):
    data = muscle_balance(days)
    if not data["total_sets"]:
        return "📭 ما عندي تمارين كفاية لتحليل توازن العضلات."
    lines = [f"🧩 توازن العضلات — آخر {days} أيام", ""]
    for muscle, score in data["scores"]:
        lines.append(f"• {muscle}: {score:.1f} نقطة حمل")
    values = [v for _, v in data["scores"] if v > 0]
    if values:
        avg = mean(values)
        low = [m for m, v in data["scores"] if v < avg * 0.45]
        if low:
            lines += ["", f"⚠️ الأقل مقارنة بالباقي: {', '.join(low[:3])}"]
    return "\n".join(lines)


def progress_report():
    done = gym_tracker.get_all_exercises_done()
    if not done:
        return "📭 ما فيه سجل كفاية لقياس التقدم."
    up, flat, down = [], [], []
    for item in done:
        t = get_exercise_trend(item["day_key"], item["exercise"])
        if t["status"] == "up":
            up.append((item["exercise"], t))
        elif t["status"] == "down":
            down.append((item["exercise"], t))
        elif t["status"] == "flat":
            flat.append((item["exercise"], t))
    lines = ["📈 تحليل التقدم", ""]
    if up:
        lines.append("🔥 يتطور:")
        lines.extend(f"• {name}: {t['change_pct']:+.1f}%" for name, t in up[:5])
    if down:
        lines += ["", "⚠️ يحتاج انتباه:"]
        lines.extend(f"• {name}: {t['change_pct']:+.1f}%" for name, t in down[:5])
    if flat:
        lines += ["", f"➖ ثابت: {len(flat)} تمرين"]
    if not up and not down and not flat:
        lines.append("نحتاج جلسات أكثر قبل ما أحكم على اتجاهك.")
    return "\n".join(lines)


def today_plan(today_data):
    r = calculate_readiness(today_data)
    recent = gym_tracker.get_recent_workout_days(limit=4)
    last_day_key = recent[0]["day_key"] if recent else None
    order = list(gym_tracker.WORKOUT_PLAN.keys())
    if last_day_key in order:
        suggested_key = order[(order.index(last_day_key) + 1) % len(order)]
    else:
        suggested_key = order[0]
    label = gym_tracker.WORKOUT_PLAN[suggested_key]["label"]

    if r["score"] < 50:
        decision = "راحة أو مشي خفيف 20–30 دقيقة"
        note = "اليوم لا تطارد أرقام جديدة. ركّز على النوم والأكل والسوائل."
    elif r["score"] < 65:
        decision = f"{label} بشدة خفيفة"
        note = "خفف أوزانك 10–15% واترك 3 تكرارات احتياط."
    elif r["score"] < 80:
        decision = f"{label} بشدة متوسطة"
        note = "تمرّن طبيعي، لكن لا تجبر نفسك على PR إذا الأداء مو حاضر."
    else:
        decision = f"{label} — يوم مناسب للأداء القوي"
        note = "جرب تطوير تمرين أو اثنين فقط، مو كل الجلسة."

    return (
        f"🎯 وش تسوي اليوم؟\n\n"
        f"⚡ الجاهزية: {r['score']}/100 — {r['label']}\n"
        f"✅ القرار: {decision}\n\n"
        f"💡 {note}\n"
        f"📌 {r['load_note']}"
    )


def format_next_suggestions(day_key=None):
    done = gym_tracker.get_all_exercises_done()
    if day_key:
        done = [x for x in done if x["day_key"] == day_key]
    suggestions = []
    for item in done:
        rec = recommend_next_weight(item["day_key"], item["exercise"])
        if rec:
            suggestions.append((item["exercise"], rec))
    if not suggestions:
        return "📭 سجّل جلستين على الأقل لبعض التمارين عشان أعطيك اقتراحات أدق."
    lines = ["🎯 اقتراحات الجلسة القادمة", ""]
    for name, rec in suggestions[:8]:
        lines.append(f"• {name}\n  {rec['text']} — {rec['trend']['text']}")
    return "\n".join(lines)


def weekly_report(today_data=None):
    load = gym_tracker.get_training_load(days=7)
    balance = muscle_balance(7)
    prs = gym_tracker.get_recent_prs(days=7)
    dates = gym_tracker.get_workout_dates(limit=7)
    total_sets = load["sets"]
    volume = load["volume"]
    lines = ["📊 تقريرك الأسبوعي", ""]
    lines.append(f"🏋️ أيام التمرين: {load['workout_days']}")
    lines.append(f"🔁 مجموع الجولات: {total_sets}")
    lines.append(f"⚙️ حجم التدريب: {volume:,.0f} كجم")
    if today_data:
        r = calculate_readiness(today_data)
        lines.append(f"⚡ جاهزية اليوم: {r['score']}/100")
    if balance["scores"]:
        top = balance["scores"][0][0]
        low = balance["scores"][-1][0]
        lines.append(f"💪 أعلى حمل عضلي: {top}")
        lines.append(f"🧩 الأقل حملًا: {low}")
    lines.append(f"🏆 أرقام شخصية هذا الأسبوع: {len(prs)}")
    if prs:
        lines.extend(f"• {p['message']}" for p in prs[:5])
    lines += ["", "🧠 توصية الأسبوع القادم:"]
    if load["workout_days"] >= 6:
        lines.append("خفف يوم واحد أو اجعله تعافي خفيف؛ الاستمرارية أهم من الضغط اليومي.")
    elif load["workout_days"] <= 2:
        lines.append("ارفع الالتزام تدريجيًا إلى 3–5 أيام حسب برنامجك وتعافيك.")
    else:
        lines.append("استمر بنفس عدد الأيام وحاول تطوير 1–2 تمرين فقط كل أسبوع.")
    return "\n".join(lines)


def coach_context(today_data):
    """سياق مختصر يضاف للمدرب الذكي."""
    try:
        r = calculate_readiness(today_data)
        load = gym_tracker.get_training_load(days=7)
        return (
            f"الجاهزية الحالية: {r['score']}/100 ({r['label']}). "
            f"شدة اليوم المناسبة: {r['intensity']}. "
            f"حمل آخر 7 أيام: {load['workout_days']} أيام، {load['sets']} جولات، "
            f"حجم {load['volume']:.0f} كجم. {r['load_note']}."
        )
    except Exception:
        return ""
