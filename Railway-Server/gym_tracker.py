"""
gym_tracker.py — تتبّع تمارين الحديد + سجل تاريخي + تاريخ محادثة الـ AI.
"""

import os
import sqlite3
import datetime

DB_PATH = os.environ.get("GYM_DB_PATH", "gym_data.db")

DEFAULT_WORKOUT_PLAN = {
    "d1": {
        "label": "🍗 صدر وباي",
        "exercises": [
            "صدر مستوي بار (Barbell Bench Press)",
            "صدر مستوي جهاز (Machine Chest Press)",
            "دامبل مستوي (Dumbbell Press)",
            "جهاز صدر سفلي (Decline Chest Press)",
            "جهاز صدر عالي (Incline Chest Press)",
            "جهاز تفتيح صدر (Chest Fly)",
            "تبادل دامبل باي (Alternating DB Curl)",
            "بار واسع باي (Barbell Biceps Curl)",
            "هامر دامبل باي (Hammer Curl)",
            "تكوير باي (Concentrated Curl)",
        ],
    },
    "d2": {
        "label": "🏋️ ظهر وتراي",
        "exercises": [
            "سحب امامي واسع (Lat Pulldown)",
            "منشار دامبل (Dumbbell Row)",
            "منشار جهاز (Seated Row Machine)",
            "سحب امامي ضيق بالمثلث (Close Grip Pulldown)",
            "سحب ارضي ضيق بالمثلث (Seated Cable Row)",
            "تي بار (T-Bar Row)",
            "اسفل الظهر جهاز (Back Extension)",
            "مسطرة عكس تراي (Reverse Grip Pushdown)",
            "تراي حبل (Rope Pushdown)",
            "مسطرة ضيق تراي (Straight Bar Pushdown)",
            "تراي من فوق الراس (Overhead Extension)",
            "جهاز تراي غطس (Seated Dips Machine)",
        ],
    },
    "d3": {
        "label": "🎯 أكتاف",
        "exercises": [
            "رفرفة امامي (Front Raises)",
            "جهاز اكتاف (Shoulder Press Machine)",
            "دامبل بريس اكتاف (DB Shoulder Press)",
            "رفرفة جانبي (Lateral Raises)",
            "امامي بالقرص (Plate Front Raise)",
            "كتف خلفي جهاز (Rear Delt Fly)",
            "ترابيس بار (Barbell Shrugs)",
            "ترابيس دامبل (Dumbbell Shrugs)",
        ],
    },
    "d4": {
        "label": "🦵 أرجل",
        "exercises": [
            "رفرفة امامي ارجل (Leg Extension)",
            "سكوات (Squats)",
            "هاك سكوات (Hack Squats)",
            "دفاع / ليج بريس (Leg Press)",
            "رفرفة خلفي ارجل (Leg Curls)",
            "طعن (Lunges)",
            "جهاز داخلي (Hip Adductor)",
            "بطات جهاز (Calf Raise)",
        ],
    },
}


# الخطة الفعلية تُحمّل من قاعدة البيانات حتى تبقى الإضافات والحذف محفوظة بعد إعادة التشغيل.
WORKOUT_PLAN = {k: {"label": v["label"], "exercises": list(v["exercises"])} for k, v in DEFAULT_WORKOUT_PLAN.items()}

def _refresh_workout_plan():
    global WORKOUT_PLAN
    plan = {k: {"label": v["label"], "exercises": []} for k, v in DEFAULT_WORKOUT_PLAN.items()}
    try:
        with _connect() as conn:
            rows = conn.execute(
                "SELECT day_key, exercise FROM exercise_plan ORDER BY day_key, sort_order, id"
            ).fetchall()
        for row in rows:
            if row["day_key"] in plan:
                plan[row["day_key"]]["exercises"].append(row["exercise"])
        WORKOUT_PLAN = plan
    except sqlite3.OperationalError:
        pass
    return WORKOUT_PLAN

def get_workout_plan():
    return _refresh_workout_plan()

def get_day_plan(day_key):
    return get_workout_plan().get(day_key)

def add_exercise(day_key, exercise):
    exercise = " ".join((exercise or "").strip().split())
    if day_key not in DEFAULT_WORKOUT_PLAN:
        raise ValueError("يوم التمرين غير موجود")
    if len(exercise) < 2 or len(exercise) > 100:
        raise ValueError("اسم التمرين لازم يكون بين 2 و100 حرف")
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM exercise_plan WHERE day_key=? AND lower(exercise)=lower(?)",
            (day_key, exercise),
        ).fetchone()
        if exists:
            raise ValueError("التمرين موجود مسبقًا في هذا اليوم")
        row = conn.execute(
            "SELECT COALESCE(MAX(sort_order),0) AS m FROM exercise_plan WHERE day_key=?",
            (day_key,),
        ).fetchone()
        conn.execute(
            "INSERT INTO exercise_plan(day_key, exercise, sort_order, created_at) VALUES(?,?,?,?)",
            (day_key, exercise, int(row["m"] or 0) + 1, datetime.datetime.utcnow().isoformat()),
        )
    _refresh_workout_plan()
    return exercise

def delete_exercise(day_key, exercise):
    with _connect() as conn:
        cur = conn.execute(
            "DELETE FROM exercise_plan WHERE day_key=? AND exercise=?",
            (day_key, exercise),
        )
        if cur.rowcount < 1:
            return False
    _refresh_workout_plan()
    return True

def update_set(day_key, exercise, set_number, reps, weight):
    today = datetime.datetime.utcnow().date().isoformat()
    with _connect() as conn:
        cur = conn.execute(
            "UPDATE sets SET reps=?, weight=? WHERE day_key=? AND exercise=? AND set_number=? AND logged_at LIKE ?",
            (int(reps), float(weight), day_key, exercise, int(set_number), f"{today}%"),
        )
        return cur.rowcount > 0


def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS sets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                day_key TEXT NOT NULL,
                exercise TEXT NOT NULL,
                set_number INTEGER NOT NULL,
                reps INTEGER NOT NULL,
                weight REAL NOT NULL,
                logged_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS pending (
                chat_id TEXT PRIMARY KEY,
                day_key TEXT NOT NULL,
                exercise TEXT NOT NULL,
                set_number INTEGER NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS chat_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS exercise_plan (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                day_key TEXT NOT NULL,
                exercise TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(day_key, exercise)
            )
        """)
        count = conn.execute("SELECT COUNT(*) AS c FROM exercise_plan").fetchone()["c"]
        if count == 0:
            now = datetime.datetime.utcnow().isoformat()
            for day_key, info in DEFAULT_WORKOUT_PLAN.items():
                for order, exercise in enumerate(info["exercises"], start=1):
                    conn.execute(
                        "INSERT OR IGNORE INTO exercise_plan(day_key, exercise, sort_order, created_at) VALUES(?,?,?,?)",
                        (day_key, exercise, order, now),
                    )
    _refresh_workout_plan()


# ---------------------------------------------------------------------------
# تسجيل التمارين
# ---------------------------------------------------------------------------

def start_exercise(chat_id, day_key, exercise):
    today = datetime.datetime.utcnow().date().isoformat()
    with _connect() as conn:
        conn.execute("DELETE FROM pending WHERE chat_id = ?", (chat_id,))
        # نكمل من بعد آخر جولة مسجّلة اليوم لنفس التمرين (يمنع تكرار أرقام الجولات)
        row = conn.execute(
            "SELECT MAX(set_number) AS max_set FROM sets "
            "WHERE day_key=? AND exercise=? AND logged_at LIKE ?",
            (day_key, exercise, f"{today}%"),
        ).fetchone()
        next_set = (row["max_set"] or 0) + 1
        conn.execute(
            "INSERT INTO pending (chat_id, day_key, exercise, set_number) VALUES (?, ?, ?, ?)",
            (chat_id, day_key, exercise, next_set),
        )


def get_pending(chat_id):
    with _connect() as conn:
        row = conn.execute("SELECT * FROM pending WHERE chat_id = ?", (chat_id,)).fetchone()
        return dict(row) if row else None


def clear_pending(chat_id):
    with _connect() as conn:
        conn.execute("DELETE FROM pending WHERE chat_id = ?", (chat_id,))


def record_set(chat_id, reps, weight):
    pending = get_pending(chat_id)
    if not pending:
        return None
    now = datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        conn.execute(
            "INSERT INTO sets (day_key, exercise, set_number, reps, weight, logged_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (pending["day_key"], pending["exercise"], pending["set_number"], reps, weight, now),
        )
        conn.execute(
            "UPDATE pending SET set_number = set_number + 1 WHERE chat_id = ?",
            (chat_id,),
        )
    return pending["set_number"]


def undo_last_set(chat_id):
    pending = get_pending(chat_id)
    if not pending or pending["set_number"] <= 1:
        return None
    last_set_number = pending["set_number"] - 1
    today = datetime.datetime.utcnow().date().isoformat()
    with _connect() as conn:
        conn.execute(
            "DELETE FROM sets WHERE day_key=? AND exercise=? AND set_number=? AND logged_at LIKE ?",
            (pending["day_key"], pending["exercise"], last_set_number, f"{today}%"),
        )
        conn.execute(
            "UPDATE pending SET set_number = set_number - 1 WHERE chat_id=?",
            (chat_id,),
        )
    return last_set_number


def get_today_sets(day_key, exercise):
    today = datetime.datetime.utcnow().date().isoformat()
    with _connect() as conn:
        rows = conn.execute(
            "SELECT set_number, reps, weight FROM sets "
            "WHERE day_key = ? AND exercise = ? AND logged_at LIKE ? ORDER BY set_number",
            (day_key, exercise, f"{today}%"),
        ).fetchall()
    return [dict(r) for r in rows]


def get_last_session(day_key, exercise):
    today = datetime.datetime.utcnow().date().isoformat()
    with _connect() as conn:
        row = conn.execute(
            "SELECT logged_at FROM sets "
            "WHERE day_key = ? AND exercise = ? AND logged_at < ? "
            "ORDER BY logged_at DESC LIMIT 1",
            (day_key, exercise, today),
        ).fetchone()
        if not row:
            return None
        last_date = row["logged_at"][:10]
        rows = conn.execute(
            "SELECT set_number, reps, weight FROM sets "
            "WHERE day_key = ? AND exercise = ? AND logged_at LIKE ? ORDER BY set_number",
            (day_key, exercise, f"{last_date}%"),
        ).fetchall()
    return {"date": last_date, "sets": [dict(r) for r in rows]}


# ---------------------------------------------------------------------------
# السجل التاريخي
# ---------------------------------------------------------------------------

def get_workout_dates(limit=14):
    with _connect() as conn:
        rows = conn.execute(
            "SELECT DISTINCT substr(logged_at,1,10) AS d FROM sets ORDER BY d DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [r["d"] for r in rows]


def get_day_summary(date):
    with _connect() as conn:
        exercises = conn.execute(
            "SELECT DISTINCT day_key, exercise FROM sets WHERE logged_at LIKE ? ORDER BY id",
            (f"{date}%",),
        ).fetchall()
        result = []
        for ex in exercises:
            sets = conn.execute(
                "SELECT set_number, reps, weight FROM sets "
                "WHERE day_key=? AND exercise=? AND logged_at LIKE ? ORDER BY set_number",
                (ex["day_key"], ex["exercise"], f"{date}%"),
            ).fetchall()
            result.append({
                "day_key": ex["day_key"],
                "exercise": ex["exercise"],
                "sets": [dict(s) for s in sets],
            })
    return result


def get_all_exercises_done():
    with _connect() as conn:
        rows = conn.execute(
            "SELECT DISTINCT day_key, exercise FROM sets ORDER BY day_key, exercise",
        ).fetchall()
    return [dict(r) for r in rows]


def get_exercise_history(day_key, exercise, limit=6):
    with _connect() as conn:
        dates = conn.execute(
            "SELECT DISTINCT substr(logged_at,1,10) AS d FROM sets "
            "WHERE day_key=? AND exercise=? ORDER BY d DESC LIMIT ?",
            (day_key, exercise, limit),
        ).fetchall()
        result = []
        for row in dates:
            d = row["d"]
            sets = conn.execute(
                "SELECT set_number, reps, weight FROM sets "
                "WHERE day_key=? AND exercise=? AND logged_at LIKE ? ORDER BY set_number",
                (day_key, exercise, f"{d}%"),
            ).fetchall()
            result.append({"date": d, "sets": [dict(s) for s in sets]})
    return result



def get_history_records(limit_dates=90):
    """يرجع السجل التاريخي كاملًا مع id لكل جولة حتى يمكن تعديلها/حذفها."""
    with _connect() as conn:
        dates = conn.execute(
            "SELECT DISTINCT substr(logged_at,1,10) AS d FROM sets ORDER BY d DESC LIMIT ?",
            (int(limit_dates),),
        ).fetchall()
        result = []
        for row in dates:
            date = row["d"]
            exercises = conn.execute(
                "SELECT day_key, exercise FROM sets WHERE logged_at LIKE ? GROUP BY day_key, exercise ORDER BY MIN(id)",
                (f"{date}%",),
            ).fetchall()
            day_items = []
            for ex in exercises:
                sets = conn.execute(
                    "SELECT id, set_number, reps, weight, logged_at FROM sets "
                    "WHERE day_key=? AND exercise=? AND logged_at LIKE ? ORDER BY set_number, id",
                    (ex["day_key"], ex["exercise"], f"{date}%"),
                ).fetchall()
                day_items.append({
                    "day_key": ex["day_key"],
                    "exercise": ex["exercise"],
                    "sets": [dict(x) for x in sets],
                })
            result.append({"date": date, "exercises": day_items})
    return result


def update_history_set(set_id, reps, weight):
    """يعدل أي جولة قديمة بالـ id. نفس جدول sets الذي يقرأه الذكاء الاصطناعي."""
    with _connect() as conn:
        cur = conn.execute(
            "UPDATE sets SET reps=?, weight=? WHERE id=?",
            (int(reps), float(weight), int(set_id)),
        )
        return cur.rowcount > 0


def delete_history_set(set_id):
    """يحذف جولة تاريخية واحدة ويرتب أرقام الجولات المتبقية داخل نفس الجلسة."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT id, day_key, exercise, substr(logged_at,1,10) AS d FROM sets WHERE id=?",
            (int(set_id),),
        ).fetchone()
        if not row:
            return False
        conn.execute("DELETE FROM sets WHERE id=?", (int(set_id),))
        remaining = conn.execute(
            "SELECT id FROM sets WHERE day_key=? AND exercise=? AND logged_at LIKE ? ORDER BY set_number, id",
            (row["day_key"], row["exercise"], f"{row['d']}%"),
        ).fetchall()
        for number, item in enumerate(remaining, start=1):
            conn.execute("UPDATE sets SET set_number=? WHERE id=?", (number, item["id"]))
        return True

# ---------------------------------------------------------------------------
# تاريخ محادثة الـ AI (multi-turn)
# ---------------------------------------------------------------------------

def save_message(chat_id, role, content):
    """يحفظ رسالة بتاريخ المحادثة ويحذف القديم (أكثر من 20 رسالة)."""
    now = datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        conn.execute(
            "INSERT INTO chat_history (chat_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            (chat_id, role, content, now),
        )
        conn.execute("""
            DELETE FROM chat_history
            WHERE chat_id = ? AND id NOT IN (
                SELECT id FROM chat_history WHERE chat_id = ? ORDER BY id DESC LIMIT 20
            )
        """, (chat_id, chat_id))


def get_history(chat_id, limit=10):
    """يرجع آخر N رسائل بترتيب تصاعدي (الأقدم أولاً)."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT role, content FROM chat_history WHERE chat_id = ? ORDER BY id DESC LIMIT ?",
            (chat_id, limit),
        ).fetchall()
    return list(reversed([dict(r) for r in rows]))


def clear_history(chat_id):
    with _connect() as conn:
        conn.execute("DELETE FROM chat_history WHERE chat_id = ?", (chat_id,))

# ---------------------------------------------------------------------------
# ذكاء الأداء: snapshots / الحمل / PR
# ---------------------------------------------------------------------------

def _local_today():
    return (datetime.datetime.utcnow() + datetime.timedelta(hours=3)).date()


def _db_today():
    """تاريخ قاعدة التمارين يطابق طريقة التخزين الحالية (UTC)."""
    return datetime.datetime.utcnow().date()


def save_health_snapshot(date_str, sleep_minutes=None, resting_hr=None, steps=None, calories=None):
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS health_snapshots (
                date TEXT PRIMARY KEY,
                sleep_minutes INTEGER,
                resting_hr REAL,
                steps INTEGER,
                calories INTEGER,
                updated_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            INSERT INTO health_snapshots(date, sleep_minutes, resting_hr, steps, calories, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                sleep_minutes=excluded.sleep_minutes,
                resting_hr=excluded.resting_hr,
                steps=excluded.steps,
                calories=excluded.calories,
                updated_at=excluded.updated_at
        """, (date_str, sleep_minutes, resting_hr, steps, calories, datetime.datetime.utcnow().isoformat()))


def get_health_baseline(days=30, exclude_date=None):
    cutoff = (_local_today() - datetime.timedelta(days=days)).isoformat()
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS health_snapshots (
                date TEXT PRIMARY KEY,
                sleep_minutes INTEGER,
                resting_hr REAL,
                steps INTEGER,
                calories INTEGER,
                updated_at TEXT NOT NULL
            )
        """)
        query = "SELECT * FROM health_snapshots WHERE date >= ?"
        params = [cutoff]
        if exclude_date:
            query += " AND date != ?"
            params.append(exclude_date)
        rows = conn.execute(query, params).fetchall()
    rows = [dict(r) for r in rows]
    def avg(key):
        vals = [float(r[key]) for r in rows if r.get(key) is not None]
        return (sum(vals) / len(vals), len(vals)) if vals else (None, 0)
    sleep, sleep_n = avg("sleep_minutes")
    rhr, rhr_n = avg("resting_hr")
    steps, steps_n = avg("steps")
    return {
        "sleep_minutes": sleep,
        "sleep_minutes_count": sleep_n,
        "resting_hr": rhr,
        "resting_hr_count": rhr_n,
        "steps": steps,
        "steps_count": steps_n,
    }


def get_sets_since(days=7):
    cutoff = (_local_today() - datetime.timedelta(days=days - 1)).isoformat()
    with _connect() as conn:
        rows = conn.execute(
            "SELECT day_key, exercise, set_number, reps, weight, logged_at FROM sets "
            "WHERE substr(logged_at,1,10) >= ? ORDER BY logged_at",
            (cutoff,),
        ).fetchall()
    return [dict(r) for r in rows]


def get_training_load(days=7):
    rows = get_sets_since(days)
    dates = {r["logged_at"][:10] for r in rows}
    volume = sum(float(r["weight"]) * int(r["reps"]) for r in rows)
    return {"workout_days": len(dates), "sets": len(rows), "volume": volume}


def get_recent_workout_days(limit=4):
    with _connect() as conn:
        rows = conn.execute("""
            SELECT substr(logged_at,1,10) AS date, day_key, MAX(logged_at) AS latest
            FROM sets GROUP BY substr(logged_at,1,10), day_key
            ORDER BY latest DESC LIMIT ?
        """, (limit,)).fetchall()
    return [dict(r) for r in rows]


def get_previous_best(day_key, exercise, exclude_today=True):
    params = [day_key, exercise]
    where = "day_key=? AND exercise=?"
    if exclude_today:
        where += " AND substr(logged_at,1,10) < ?"
        params.append(_db_today().isoformat())
    with _connect() as conn:
        rows = conn.execute(
            f"SELECT reps, weight FROM sets WHERE {where}", params
        ).fetchall()
    if not rows:
        return {"max_weight": None, "max_reps_at_weight": {}, "best_e1rm": None}
    max_weight = max(float(r["weight"]) for r in rows)
    reps_by_weight = {}
    best_e1rm = 0
    for r in rows:
        w = float(r["weight"])
        reps = int(r["reps"])
        reps_by_weight[w] = max(reps_by_weight.get(w, 0), reps)
        best_e1rm = max(best_e1rm, w * (1 + reps / 30))
    return {"max_weight": max_weight, "max_reps_at_weight": reps_by_weight, "best_e1rm": best_e1rm}


def save_pr(chat_id, day_key, exercise, message):
    now = datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS personal_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id TEXT NOT NULL,
                day_key TEXT NOT NULL,
                exercise TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        conn.execute(
            "INSERT INTO personal_records(chat_id, day_key, exercise, message, created_at) VALUES (?, ?, ?, ?, ?)",
            (chat_id, day_key, exercise, message, now),
        )


def get_recent_prs(days=7):
    cutoff = (_local_today() - datetime.timedelta(days=days - 1)).isoformat()
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS personal_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id TEXT NOT NULL,
                day_key TEXT NOT NULL,
                exercise TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        rows = conn.execute(
            "SELECT day_key, exercise, message, created_at FROM personal_records "
            "WHERE substr(created_at,1,10) >= ? ORDER BY created_at DESC",
            (cutoff,),
        ).fetchall()
    return [dict(r) for r in rows]


def notification_sent(key, date_str=None):
    date_str = date_str or _local_today().isoformat()
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS notification_log (
                key TEXT NOT NULL,
                date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(key, date)
            )
        """)
        row = conn.execute("SELECT 1 FROM notification_log WHERE key=? AND date=?", (key, date_str)).fetchone()
    return bool(row)


def mark_notification_sent(key, date_str=None):
    date_str = date_str or _local_today().isoformat()
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS notification_log (
                key TEXT NOT NULL,
                date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(key, date)
            )
        """)
        conn.execute(
            "INSERT OR IGNORE INTO notification_log(key, date, created_at) VALUES (?, ?, ?)",
            (key, date_str, datetime.datetime.utcnow().isoformat()),
        )


def get_best_before_set(day_key, exercise, current_set_number):
    """أفضل الأرقام قبل الجولة الحالية (يشمل الأيام السابقة وجولات اليوم الأقدم)."""
    today = _db_today().isoformat()
    with _connect() as conn:
        rows = conn.execute("""
            SELECT reps, weight FROM sets
            WHERE day_key=? AND exercise=?
              AND NOT (substr(logged_at,1,10)=? AND set_number=?)
        """, (day_key, exercise, today, current_set_number)).fetchall()
    if not rows:
        return {"max_weight": None, "max_reps_at_weight": {}, "best_e1rm": None}
    max_weight = max(float(r["weight"]) for r in rows)
    reps_by_weight = {}
    best_e1rm = 0
    for r in rows:
        w = float(r["weight"])
        reps = int(r["reps"])
        reps_by_weight[w] = max(reps_by_weight.get(w, 0), reps)
        best_e1rm = max(best_e1rm, w * (1 + reps / 30))
    return {"max_weight": max_weight, "max_reps_at_weight": reps_by_weight, "best_e1rm": best_e1rm}
