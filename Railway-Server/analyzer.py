"""
analyzer.py — النسخة المطورة
جديد:
- /sleep يعرض جدول زمني كامل للمراحل (متى العميق، متى الأحلام...).
- النبض يعرض اللحظي + الراحة مع بعض.
"""

from datetime import datetime

STEP_GOAL = 10000  # الهدف اليومي؛ عدّله لو هدفك مختلف

STAGE_LABELS = {
    "DEEP": "🌑 عميق",
    "LIGHT": "🌗 خفيف",
    "REM": "👁️ أحلام (REM)",
    "AWAKE": "⏰ يقظة",
    "WAKE": "⏰ يقظة",
}


def _to_int(value):
    if value is None:
        return None
    try:
        return int(float(value))
    except (ValueError, TypeError):
        return None


def _fmt_minutes(total_minutes):
    total_minutes = _to_int(total_minutes)
    if total_minutes is None:
        return None
    h, m = divmod(total_minutes, 60)
    return f"{h} س {m} د" if h else f"{m} دقيقة"


def _fmt_clock(dt):
    """يحول datetime إلى وقت 12 ساعة بالعربي مثل 11:30م."""
    if dt is None:
        return "؟"
    hour = dt.hour % 12 or 12
    suffix = "ص" if dt.hour < 12 else "م"
    return f"{hour}:{dt.minute:02d}{suffix}"


def _steps_verdict(steps):
    steps = _to_int(steps)
    if steps is None:
        return ""
    pct = int(steps / STEP_GOAL * 100)
    if pct >= 100:
        return f"✅ وصلت هدفك اليومي ({pct}%) — ممتاز!"
    if pct >= 70:
        return f"👍 قربت من هدفك ({pct}% من {STEP_GOAL:,})"
    if pct >= 40:
        return f"🚶 بمنتصف الطريق ({pct}% من {STEP_GOAL:,})"
    return f"💡 لسا بالبداية ({pct}% من {STEP_GOAL:,}) — مشية خفيفة تفرق"


def _rhr_verdict(bpm):
    bpm = _to_int(bpm)
    if bpm is None:
        return ""
    if bpm < 60:
        return "(ممتاز — نطاق الرياضيين عادة)"
    if bpm <= 80:
        return "(طبيعي وصحي 👍)"
    if bpm <= 100:
        return "(ضمن الطبيعي، بس الأقل أفضل)"
    return "(مرتفع — لو استمر استشر طبيب)"


def _sleep_verdict(minutes):
    minutes = _to_int(minutes)
    if minutes is None:
        return ""
    hours = minutes / 60
    if hours >= 7:
        return "✅ نوم كافي (7+ ساعات هو الموصى به للبالغين)"
    if hours >= 6:
        return "😐 أقل من الموصى به شوي (حاول توصل 7 ساعات)"
    return "⚠️ نوم قليل — جسمك يحتاج أكثر"


def format_today_message(data):
    date_str = data.get("date", "")
    try:
        date_str = datetime.fromisoformat(date_str).strftime("%d-%m-%Y")
    except Exception:
        pass

    lines = [f"📊 ملخصك اليومي — {date_str}", "═══════════════════", ""]

    steps = _to_int(data.get("steps"))
    lines.append("👣 الخطوات")
    if steps is not None:
        lines.append(f"   {steps:,} خطوة")
        lines.append(f"   {_steps_verdict(steps)}")
    else:
        lines.append("   لا توجد بيانات بعد (زامن ساعتك مع التطبيق)")
    lines.append("")

    sleep = data.get("sleep")
    lines.append("😴 النوم (آخر ليلة)")
    if sleep:
        summary = sleep.get("summary", {})
        minutes = _to_int(summary.get("minutesAsleep"))
        start, end = sleep.get("_local_start"), sleep.get("_local_end")
        if start and end:
            lines.append(f"   🛏️ {_fmt_clock(start)} → {_fmt_clock(end)}")
        lines.append(f"   نمت: {_fmt_minutes(minutes)}")
        lines.append(f"   {_sleep_verdict(minutes)}")
    else:
        lines.append("   لا توجد جلسة نوم مسجلة بآخر 48 ساعة")
    lines.append("")

    # النبض: اللحظي + الراحة مع بعض
    lines.append("❤️ نبضك")
    current = data.get("current_hr")
    if current:
        bpm, when = current
        when_str = f" (الساعة {_fmt_clock(when)})" if when else ""
        lines.append(f"   الحالي: {bpm} نبضة/دقيقة{when_str}")
    rhr = _to_int(data.get("heart_rate"))
    if rhr is not None:
        lines.append(f"   💤 معدل الراحة: {rhr} {_rhr_verdict(rhr)}")
        lines.append("   💡 معدل الراحة هو مؤشر لياقتك الحقيقي")
    if not current and rhr is None:
        lines.append("   لا توجد قراءات حديثة")
    lines.append("")

    cal = _to_int(data.get("calories"))
    lines.append("🔥 السعرات المحروقة")
    if cal is not None:
        lines.append(f"   {cal:,} سعرة حتى الآن")
        lines.append("   💡 تشمل حرق جسمك الأساسي + نشاطك (ترتفع مع اليوم)")
    else:
        lines.append("   لا توجد بيانات بعد")

    return "\n".join(lines)


def format_week_message(days):
    if not days:
        return "تعذر جلب بيانات الأسبوع."

    for d in days:
        d["steps"] = _to_int(d.get("steps"))
        d["calories"] = _to_int(d.get("calories"))

    valid_steps = [d["steps"] for d in days if d.get("steps")]
    avg_steps = sum(valid_steps) / len(valid_steps) if valid_steps else None
    best_day = max((d for d in days if d.get("steps")), key=lambda d: d["steps"], default=None)

    day_names = {0: "الاثنين", 1: "الثلاثاء", 2: "الأربعاء", 3: "الخميس",
                 4: "الجمعة", 5: "السبت", 6: "الأحد"}

    lines = ["📅 أسبوعك بنظرة وحدة", "═══════════════════", ""]
    for d in days:
        try:
            dt = datetime.fromisoformat(d["date"])
            label = f"{day_names[dt.weekday()]} {dt.strftime('%d-%m')}"
        except Exception:
            label = d["date"]
        steps_str = f"{d['steps']:,}" if d.get("steps") else "—"
        cal_str = f" | 🔥 {d['calories']:,}" if d.get("calories") else ""
        marker = " ⭐" if best_day and d["date"] == best_day["date"] else ""
        lines.append(f"• {label}: 👣 {steps_str}{cal_str}{marker}")

    lines.append("")
    if avg_steps:
        lines.append(f"📈 متوسطك: {int(avg_steps):,} خطوة/يوم")
        if best_day:
            lines.append(f"⭐ أفضل يوم: {best_day['steps']:,} خطوة")
        today_steps = days[-1].get("steps")
        if today_steps:
            diff = today_steps - avg_steps
            if diff >= 0:
                lines.append(f"✅ اليوم فوق متوسطك بـ {int(diff):,} خطوة — استمر!")
            else:
                lines.append(f"💡 اليوم تحت متوسطك بـ {int(abs(diff)):,} — فيه وقت تعوض")

    return "\n".join(lines)


def format_sleep_message(sleep):
    if not sleep:
        return ("😴 ما فيه جلسة نوم مسجلة بآخر 48 ساعة.\n"
                "💡 تأكد إنك لابس الساعة وقت النوم وإن التطبيق زامن.")

    summary = sleep.get("summary", {})
    minutes = _to_int(summary.get("minutesAsleep"))
    start, end = sleep.get("_local_start"), sleep.get("_local_end")

    lines = ["😴 تحليل نومك — آخر ليلة", "═══════════════════", ""]
    if start and end:
        lines.append(f"🛏️ نمت: {_fmt_clock(start)} → صحيت: {_fmt_clock(end)}")
    lines.append(f"⏱️ إجمالي النوم: {_fmt_minutes(minutes)}")
    lines.append(f"{_sleep_verdict(minutes)}")
    awake = _to_int(summary.get("minutesAwake"))
    if awake is not None:
        lines.append(f"🌙 صحيت أثناء الليل: {_fmt_minutes(awake)} (طبيعي لو أقل من ساعة)")

    # الجدول الزمني للمراحل
    timeline = sleep.get("_stages_timeline") or []
    # نعرض فقط الفترات المهمة (عميق وREM) بالتفصيل + ملخص للباقي
    detailed = [s for s in timeline
                if s.get("type") in ("DEEP", "REM") and s.get("start") and s.get("end")]
    if detailed:
        lines.append("")
        lines.append("🕐 متى صارت مراحلك المهمة:")
        for s in detailed:
            label = STAGE_LABELS.get(s["type"], s["type"])
            dur = f" ({_fmt_minutes(s['minutes'])})" if s.get("minutes") else ""
            lines.append(f"  {label}: {_fmt_clock(s['start'])}–{_fmt_clock(s['end'])}{dur}")

    # المجاميع لكل مرحلة
    stages_totals = {s.get("type"): _to_int(s.get("minutes"))
                     for s in summary.get("stagesSummary", [])}
    if stages_totals:
        lines.append("")
        lines.append("📊 مجاميع الليلة:")
        if stages_totals.get("DEEP"):
            lines.append(f"  🌑 عميق: {_fmt_minutes(stages_totals['DEEP'])} — يرمم جسمك (المثالي 1-2 ساعة)")
        if stages_totals.get("REM"):
            lines.append(f"  👁️ أحلام: {_fmt_minutes(stages_totals['REM'])} — مهم للذاكرة والمزاج")
        if stages_totals.get("LIGHT"):
            lines.append(f"  🌗 خفيف: {_fmt_minutes(stages_totals['LIGHT'])} — طبيعي يكون الأغلب")

    return "\n".join(lines)


def format_heart_message(rhr, current=None):
    """rhr = معدل الراحة، current = (bpm, local_dt) أو None."""
    lines = ["❤️ نبضك", "═══════════════════", ""]

    if current:
        bpm, when = current
        when_str = f" — آخر قراءة الساعة {_fmt_clock(when)}" if when else ""
        lines.append(f"⚡ الحالي: {bpm} نبضة/دقيقة{when_str}")
        lines.append("   (يتغير طبيعيًا مع الحركة والقهوة والتوتر)")
        lines.append("")

    rhr = _to_int(rhr)
    if rhr is not None:
        lines.append(f"💤 معدل الراحة: {rhr} نبضة/دقيقة {_rhr_verdict(rhr)}")
        lines.append("")
        lines.append("💡 وش الفرق؟")
        lines.append("الحالي = نبضك هالحين (يرتفع مع أي نشاط).")
        lines.append("الراحة = نبضك بأعمق استرخاء — هذا مؤشر لياقتك الحقيقي.")
        lines.append("راقب معدل الراحة أسبوعيًا: نزوله التدريجي = لياقتك تتحسن.")
    elif not current:
        return ("❤️ لا توجد قراءات حديثة للنبض.\n"
                "💡 البس الساعة فترة أطول وزامن التطبيق.")

    return "\n".join(lines)


def format_activity_message(data):
    lines = ["🏃 نشاطك اليوم", "═══════════════════", ""]
    steps = _to_int(data.get("steps"))
    cal = _to_int(data.get("calories"))
    if steps is not None:
        km = steps * 0.00075
        lines.append(f"👣 {steps:,} خطوة (~{km:.1f} كم تقريبًا)")
        lines.append(f"{_steps_verdict(steps)}")
    else:
        lines.append("👣 لا توجد بيانات خطوات بعد")
    lines.append("")
    if cal is not None:
        lines.append(f"🔥 {cal:,} سعرة محروقة حتى الآن")
    else:
        lines.append("🔥 لا توجد بيانات سعرات بعد")
    return "\n".join(lines)
