"""
gym_tracker.py — تتبّع تمارين الحديد + سجل تاريخي + تاريخ محادثة الـ AI.
"""

import os
import sqlite3
import datetime
import uuid

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


# الخطة الفعلية تُحمّل من قاعدة البيانات حتى تبقى الإضافات والحذف والتسمية محفوظة.
WORKOUT_PLAN = {k: {"label": v["label"], "exercises": list(v["exercises"])} for k, v in DEFAULT_WORKOUT_PLAN.items()}

def _refresh_workout_plan():
    """يبني البرنامج من workout_sections + exercise_plan. يدعم أقسامًا مخصصة بالكامل."""
    global WORKOUT_PLAN
    plan = {}
    try:
        with _connect() as conn:
            sections = conn.execute(
                "SELECT day_key, label FROM workout_sections ORDER BY sort_order, rowid"
            ).fetchall()
            for section in sections:
                plan[section["day_key"]] = {"label": section["label"], "exercises": []}

            rows = conn.execute(
                "SELECT day_key, exercise FROM exercise_plan ORDER BY day_key, sort_order, id"
            ).fetchall()
            for row in rows:
                if row["day_key"] in plan:
                    plan[row["day_key"]]["exercises"].append(row["exercise"])

        WORKOUT_PLAN = plan
    except sqlite3.OperationalError:
        # قبل اكتمال migration أثناء أول تشغيل.
        pass
    return WORKOUT_PLAN

def get_workout_plan():
    return _refresh_workout_plan()

def get_day_plan(day_key):
    return get_workout_plan().get(day_key)

def _clean_name(value, min_len=2, max_len=100, field_name="الاسم"):
    value = " ".join((value or "").strip().split())
    if len(value) < min_len or len(value) > max_len:
        raise ValueError(f"{field_name} لازم يكون بين {min_len} و{max_len} حرف")
    return value

def add_section(label):
    label = _clean_name(label, field_name="اسم القسم")
    day_key = "c_" + uuid.uuid4().hex[:10]
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM workout_sections WHERE lower(label)=lower(?)",
            (label,),
        ).fetchone()
        if exists:
            raise ValueError("يوجد قسم بنفس الاسم")
        row = conn.execute(
            "SELECT COALESCE(MAX(sort_order),0) AS m FROM workout_sections"
        ).fetchone()
        conn.execute(
            "INSERT INTO workout_sections(day_key, label, sort_order, created_at) VALUES(?,?,?,?)",
            (day_key, label, int(row["m"] or 0) + 1, datetime.datetime.utcnow().isoformat()),
        )
    _refresh_workout_plan()
    return day_key

def rename_section(day_key, new_label):
    new_label = _clean_name(new_label, field_name="اسم القسم")
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM workout_sections WHERE lower(label)=lower(?) AND day_key<>?",
            (new_label, day_key),
        ).fetchone()
        if exists:
            raise ValueError("يوجد قسم بنفس الاسم")
        cur = conn.execute(
            "UPDATE workout_sections SET label=? WHERE day_key=?",
            (new_label, day_key),
        )
        if cur.rowcount < 1:
            raise ValueError("القسم غير موجود")
    _refresh_workout_plan()
    return True

def delete_section(day_key):
    """يحذف القسم من البرنامج الحالي فقط. السجل القديم يبقى للـAI والتقارير."""
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM workout_sections WHERE day_key=?",
            (day_key,),
        ).fetchone()
        if not exists:
            return False
        conn.execute("DELETE FROM exercise_plan WHERE day_key=?", (day_key,))
        conn.execute("DELETE FROM workout_sections WHERE day_key=?", (day_key,))
        conn.execute("DELETE FROM pending WHERE day_key=?", (day_key,))
    _refresh_workout_plan()
    return True

def add_exercise(day_key, exercise):
    exercise = _clean_name(exercise, field_name="اسم التمرين")
    with _connect() as conn:
        section = conn.execute(
            "SELECT 1 FROM workout_sections WHERE day_key=?",
            (day_key,),
        ).fetchone()
        if not section:
            raise ValueError("قسم التمرين غير موجود")
        exists = conn.execute(
            "SELECT 1 FROM exercise_plan WHERE day_key=? AND lower(exercise)=lower(?)",
            (day_key, exercise),
        ).fetchone()
        if exists:
            raise ValueError("التمرين موجود مسبقًا في هذا القسم")
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

def rename_exercise(day_key, old_name, new_name):
    """
    يغير اسم التمرين في البرنامج وفي السجل التاريخي نفسه.
    بهذا يبقى تاريخ الأوزان متصلًا ويقرأه الـAI كتمرين واحد.
    """
    old_name = _clean_name(old_name, field_name="اسم التمرين الحالي")
    new_name = _clean_name(new_name, field_name="الاسم الجديد")
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM exercise_plan WHERE day_key=? AND exercise=?",
            (day_key, old_name),
        ).fetchone()
        if not exists:
            raise ValueError("التمرين غير موجود")

        duplicate = conn.execute(
            "SELECT 1 FROM exercise_plan WHERE day_key=? AND lower(exercise)=lower(?) AND exercise<>?",
            (day_key, new_name, old_name),
        ).fetchone()
        if duplicate:
            raise ValueError("يوجد تمرين بنفس الاسم داخل القسم")

        conn.execute(
            "UPDATE exercise_plan SET exercise=? WHERE day_key=? AND exercise=?",
            (new_name, day_key, old_name),
        )
        conn.execute(
            "UPDATE sets SET exercise=? WHERE day_key=? AND exercise=?",
            (new_name, day_key, old_name),
        )
        conn.execute(
            "UPDATE pending SET exercise=? WHERE day_key=? AND exercise=?",
            (new_name, day_key, old_name),
        )
        # جدول PR قد لا يكون منشأ في بعض النسخ؛ نحافظ على التوافق.
        try:
            conn.execute(
                "UPDATE personal_records SET exercise=? WHERE day_key=? AND exercise=?",
                (new_name, day_key, old_name),
            )
        except sqlite3.OperationalError:
            pass
    _refresh_workout_plan()
    return True

def delete_exercise(day_key, exercise):
    """يحذف التمرين من البرنامج الحالي فقط؛ السجل التاريخي لا يُحذف."""
    with _connect() as conn:
        cur = conn.execute(
            "DELETE FROM exercise_plan WHERE day_key=? AND exercise=?",
            (day_key, exercise),
        )
        conn.execute(
            "DELETE FROM pending WHERE day_key=? AND exercise=?",
            (day_key, exercise),
        )
        if cur.rowcount < 1:
            return False
    _refresh_workout_plan()
    return True


def _renumber_plan(conn, day_key):
    rows = conn.execute(
        "SELECT id FROM exercise_plan WHERE day_key=? ORDER BY sort_order,id",
        (day_key,),
    ).fetchall()
    for order, row in enumerate(rows, start=1):
        conn.execute("UPDATE exercise_plan SET sort_order=? WHERE id=?", (order, row["id"]))


def reorder_exercises(day_key, exercises):
    """يرتب تمارين القسم الحالي فقط بدون لمس السجل التاريخي."""
    if not isinstance(exercises, list) or not exercises:
        raise ValueError("ترتيب التمارين غير صالح")
    cleaned = [_clean_name(x, field_name="اسم التمرين") for x in exercises]
    if len({x.lower() for x in cleaned}) != len(cleaned):
        raise ValueError("يوجد تمرين مكرر في الترتيب")
    with _connect() as conn:
        current_rows = conn.execute(
            "SELECT exercise FROM exercise_plan WHERE day_key=? ORDER BY sort_order,id",
            (day_key,),
        ).fetchall()
        current = [row["exercise"] for row in current_rows]
        if {x.lower() for x in current} != {x.lower() for x in cleaned} or len(current) != len(cleaned):
            raise ValueError("قائمة التمارين تغيرت؛ حدّث الصفحة وحاول مرة ثانية")
        by_lower = {x.lower(): x for x in current}
        for order, requested in enumerate(cleaned, start=1):
            actual = by_lower[requested.lower()]
            conn.execute(
                "UPDATE exercise_plan SET sort_order=? WHERE day_key=? AND exercise=?",
                (order, day_key, actual),
            )
    _refresh_workout_plan()
    return True


def move_exercise(source_day, target_day, exercise):
    """ينقل التمرين بين أقسام البرنامج؛ الجولات التاريخية تبقى في يومها الأصلي."""
    exercise = _clean_name(exercise, field_name="اسم التمرين")
    if not source_day or not target_day:
        raise ValueError("القسم غير صالح")
    if source_day == target_day:
        return True
    with _connect() as conn:
        source = conn.execute(
            "SELECT id FROM exercise_plan WHERE day_key=? AND exercise=?",
            (source_day, exercise),
        ).fetchone()
        if not source:
            raise ValueError("التمرين غير موجود في القسم الحالي")
        target_exists = conn.execute(
            "SELECT 1 FROM workout_sections WHERE day_key=?",
            (target_day,),
        ).fetchone()
        if not target_exists:
            raise ValueError("القسم المطلوب غير موجود")
        duplicate = conn.execute(
            "SELECT 1 FROM exercise_plan WHERE day_key=? AND lower(exercise)=lower(?)",
            (target_day, exercise),
        ).fetchone()
        if duplicate:
            raise ValueError("التمرين موجود مسبقًا في القسم الآخر")
        row = conn.execute(
            "SELECT COALESCE(MAX(sort_order),0) AS m FROM exercise_plan WHERE day_key=?",
            (target_day,),
        ).fetchone()
        conn.execute(
            "UPDATE exercise_plan SET day_key=?, sort_order=? WHERE id=?",
            (target_day, int(row["m"] or 0) + 1, source["id"]),
        )
        conn.execute(
            "DELETE FROM pending WHERE day_key=? AND exercise=?",
            (source_day, exercise),
        )
        _renumber_plan(conn, source_day)
        _renumber_plan(conn, target_day)
    _refresh_workout_plan()
    return True

def _renumber_session(conn, day_key, exercise, date_str):
    rows = conn.execute(
        "SELECT id FROM sets WHERE day_key=? AND exercise=? AND logged_at LIKE ? "
        "ORDER BY set_number, id",
        (day_key, exercise, f"{date_str}%"),
    ).fetchall()
    for number, row in enumerate(rows, start=1):
        conn.execute("UPDATE sets SET set_number=? WHERE id=?", (number, row["id"]))

def record_set_direct(day_key, exercise, reps, weight):
    """
    تسجيل مباشر وآمن لتطبيق iOS.
    يحسب رقم الجولة من قاعدة البيانات داخل transaction بدل الاعتماد على pending،
    لذلك كل جولة مستقلة ولا تتكرر أرقام الجولات حتى مع إعادة فتح الشاشة.
    """
    today = datetime.datetime.utcnow().date().isoformat()
    now = datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        conn.execute("BEGIN IMMEDIATE")
        _renumber_session(conn, day_key, exercise, today)
        row = conn.execute(
            "SELECT COALESCE(MAX(set_number),0) AS m FROM sets "
            "WHERE day_key=? AND exercise=? AND logged_at LIKE ?",
            (day_key, exercise, f"{today}%"),
        ).fetchone()
        set_number = int(row["m"] or 0) + 1
        cur = conn.execute(
            "INSERT INTO sets(day_key, exercise, set_number, reps, weight, logged_at) "
            "VALUES(?,?,?,?,?,?)",
            (day_key, exercise, set_number, int(reps), float(weight), now),
        )
        set_id = cur.lastrowid
    return {"id": set_id, "set_number": set_number}

def update_set_by_id(set_id, reps, weight):
    with _connect() as conn:
        cur = conn.execute(
            "UPDATE sets SET reps=?, weight=? WHERE id=?",
            (int(reps), float(weight), int(set_id)),
        )
        return cur.rowcount > 0

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
            CREATE TABLE IF NOT EXISTS workout_sections (
                day_key TEXT PRIMARY KEY,
                label TEXT NOT NULL UNIQUE,
                sort_order INTEGER NOT NULL,
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
        conn.execute("""
            CREATE TABLE IF NOT EXISTS body_profile (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                target_weight REAL,
                daily_calories INTEGER,
                protein_grams INTEGER,
                updated_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS body_weights (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                weight REAL NOT NULL,
                logged_at TEXT NOT NULL
            )
        """)

        now = datetime.datetime.utcnow().isoformat()

        # Migration آمن: يحافظ على خطة المستخدم الحالية ويضيف جدول الأقسام فقط.
        section_count = conn.execute("SELECT COUNT(*) AS c FROM workout_sections").fetchone()["c"]
        if section_count == 0:
            for order, (day_key, info) in enumerate(DEFAULT_WORKOUT_PLAN.items(), start=1):
                conn.execute(
                    "INSERT OR IGNORE INTO workout_sections(day_key, label, sort_order, created_at) VALUES(?,?,?,?)",
                    (day_key, info["label"], order, now),
                )

            # إذا كان لدى المستخدم تمارين مضافة في مفاتيح أخرى من نسخة قديمة، لا نفقدها.
            extra_keys = conn.execute(
                "SELECT DISTINCT day_key FROM exercise_plan WHERE day_key NOT IN "
                "(SELECT day_key FROM workout_sections)"
            ).fetchall()
            next_order = len(DEFAULT_WORKOUT_PLAN) + 1
            for row in extra_keys:
                key = row["day_key"]
                conn.execute(
                    "INSERT OR IGNORE INTO workout_sections(day_key, label, sort_order, created_at) VALUES(?,?,?,?)",
                    (key, key, next_order, now),
                )
                next_order += 1

        count = conn.execute("SELECT COUNT(*) AS c FROM exercise_plan").fetchone()["c"]
        if count == 0:
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
        _renumber_session(conn, day_key, exercise, today)
        rows = conn.execute(
            "SELECT id, set_number, reps, weight FROM sets "
            "WHERE day_key = ? AND exercise = ? AND logged_at LIKE ? ORDER BY set_number, id",
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
# سياق المدرب الذكي الاحترافي — مصدره قاعدة البيانات الحالية لحظة كل سؤال
# ---------------------------------------------------------------------------

def _fmt_number(value):
    try:
        x = float(value)
        return str(int(x)) if x.is_integer() else f"{x:g}"
    except Exception:
        return str(value)


def _active_exercise_lookup():
    """يرجع البرنامج الحالي فقط. أي تمرين محذوف لا يظهر هنا."""
    plan = get_workout_plan()
    lookup = {}
    for day_key, info in plan.items():
        for exercise in info.get("exercises", []):
            lookup[(day_key, exercise)] = info.get("label", day_key)
    return plan, lookup


def _all_exercise_stats():
    """
    إحصائية مختصرة لكل تمرين ظهر في السجل، سواء لا يزال في البرنامج أو حُذف منه.
    هذا يسمح للمدرب بفهم التاريخ بدون اعتبار التمرين المحذوف ضمن البرنامج الحالي.
    """
    with _connect() as conn:
        rows = conn.execute("""
            SELECT
                day_key,
                exercise,
                COUNT(*) AS total_sets,
                COUNT(DISTINCT substr(logged_at,1,10)) AS sessions,
                MIN(substr(logged_at,1,10)) AS first_date,
                MAX(substr(logged_at,1,10)) AS last_date,
                MAX(weight) AS best_weight
            FROM sets
            GROUP BY day_key, exercise
            ORDER BY last_date DESC, exercise
        """).fetchall()
    return [dict(r) for r in rows]


def _recent_workout_context(limit_dates=14):
    records = get_history_records(limit_dates=limit_dates)
    lines = []
    for day in records:
        lines.append(f"التاريخ {day['date']}:")
        for ex in day["exercises"]:
            set_text = ", ".join(
                f"ج{s.get('set_number')}: {_fmt_number(s.get('weight'))}كجم × {s.get('reps')}"
                for s in ex.get("sets", [])
            )
            lines.append(f"- {ex['exercise']} [{ex['day_key']}]: {set_text or 'لا توجد جولات'}")
    return "\n".join(lines) if lines else "لا يوجد سجل تمارين حتى الآن."


def _exercise_progress_context(question="", max_sessions=8):
    """
    يعرض تفاصيل إضافية للتمارين المذكورة حرفيًا في السؤال.
    إذا لم يُذكر تمرين بعينه، يرجع ملخصًا مضغوطًا لكل التمارين.
    """
    plan, active_lookup = _active_exercise_lookup()
    stats = _all_exercise_stats()
    q = (question or "").casefold()

    mentioned = []
    for item in stats:
        name = item["exercise"]
        if name.casefold() in q:
            mentioned.append(item)

    if mentioned:
        lines = ["تفاصيل التمارين المذكورة في السؤال:"]
        for item in mentioned[:6]:
            key = (item["day_key"], item["exercise"])
            status = "نشط حاليًا" if key in active_lookup else "محذوف من البرنامج الحالي / تاريخي فقط"
            lines.append(f"\n{item['exercise']} — {status}")
            history = get_exercise_history(item["day_key"], item["exercise"], limit=max_sessions)
            for session in history:
                set_text = ", ".join(
                    f"ج{s.get('set_number')}: {_fmt_number(s.get('weight'))}كجم × {s.get('reps')}"
                    for s in session.get("sets", [])
                )
                lines.append(f"- {session['date']}: {set_text}")
        return "\n".join(lines)

    lines = ["ملخص كل التمارين المسجلة تاريخيًا:"]
    for item in stats:
        key = (item["day_key"], item["exercise"])
        status = "نشط" if key in active_lookup else "تاريخي/محذوف من البرنامج الحالي"
        lines.append(
            f"- {item['exercise']} [{status}] | آخر مرة {item['last_date']} | "
            f"{item['sessions']} جلسات | {item['total_sets']} جولات | "
            f"أفضل وزن {_fmt_number(item['best_weight'])}كجم"
        )
    return "\n".join(lines) if len(lines) > 1 else "لا يوجد تاريخ تمارين بعد."


def build_full_coach_context(question="", recent_dates=14):
    """
    يبني سياقًا حيًا من قاعدة البيانات لحظة السؤال.

    قواعد المصدر:
    - البرنامج الحالي يأتي من exercise_plan/workout_sections الآن.
    - التمرين الجديد يظهر فور إضافته.
    - إذا تمرّن المستخدم تمرينًا جديدًا، تظهر جولاته فور تسجيلها.
    - التمرين المحذوف لا يظهر ضمن البرنامج الحالي.
    - سجله القديم يبقى تاريخيًا وموسومًا بوضوح بأنه محذوف/غير نشط.
    """
    plan, active_lookup = _active_exercise_lookup()
    stats = _all_exercise_stats()

    current_lines = ["البرنامج الحالي الفعلي الآن:"]
    if not plan:
        current_lines.append("- لا توجد أقسام أو تمارين نشطة حاليًا.")
    else:
        for day_key, info in plan.items():
            exercises = info.get("exercises", [])
            if exercises:
                current_lines.append(
                    f"- {info.get('label', day_key)} [{day_key}]: " + "، ".join(exercises)
                )
            else:
                current_lines.append(f"- {info.get('label', day_key)} [{day_key}]: بدون تمارين")

    removed = []
    for item in stats:
        key = (item["day_key"], item["exercise"])
        if key not in active_lookup:
            removed.append(
                f"- {item['exercise']} [{item['day_key']}] — آخر تمرين {item['last_date']}"
            )

    removed_lines = ["تمارين تاريخية لم تعد في البرنامج الحالي:"]
    removed_lines += removed if removed else ["- لا يوجد."]

    recent = _recent_workout_context(limit_dates=recent_dates)
    progress = _exercise_progress_context(question=question)

    load = get_training_load(days=7)
    prs = get_recent_prs(days=14)

    metrics = [
        "ملخص الحمل التدريبي:",
        f"- آخر 7 أيام: {load['workout_days']} أيام تمرين، {load['sets']} جولات، حجم {_fmt_number(load['volume'])} كجم.",
    ]
    if prs:
        metrics.append("- أحدث الأرقام الشخصية:")
        metrics.extend(f"  • {p['exercise']}: {p['message']} ({p['created_at'][:10]})" for p in prs[:10])
    else:
        metrics.append("- لا توجد PR حديثة مسجلة.")

    return "\n\n".join([
        "\n".join(current_lines),
        "\n".join(removed_lines),
        "آخر التمارين الفعلية بالتفصيل:\n" + recent,
        progress,
        "\n".join(metrics),
        body_coach_context(),
    ])

# ---------------------------------------------------------------------------
# الوزن والهدف الشخصي
# ---------------------------------------------------------------------------

def save_body_profile(target_weight=None, daily_calories=None, protein_grams=None):
    now = datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        current = conn.execute("SELECT * FROM body_profile WHERE id=1").fetchone()
        old = dict(current) if current else {}
        conn.execute(
            "INSERT OR REPLACE INTO body_profile(id,target_weight,daily_calories,protein_grams,updated_at) VALUES(1,?,?,?,?)",
            (
                target_weight if target_weight is not None else old.get("target_weight"),
                daily_calories if daily_calories is not None else old.get("daily_calories"),
                protein_grams if protein_grams is not None else old.get("protein_grams"),
                now,
            ),
        )
    return get_body_summary()

def add_body_weight(weight, logged_at=None):
    weight = float(weight)
    if not 25 <= weight <= 350:
        raise ValueError("الوزن لازم يكون بين 25 و350 كجم")
    when = logged_at or datetime.datetime.utcnow().isoformat()
    with _connect() as conn:
        conn.execute("INSERT INTO body_weights(weight, logged_at) VALUES(?,?)", (weight, when))
    return get_body_summary()

def delete_body_weight(entry_id):
    with _connect() as conn:
        row = conn.execute("SELECT id FROM body_weights WHERE id=?", (int(entry_id),)).fetchone()
        if not row:
            return False
        conn.execute("DELETE FROM body_weights WHERE id=?", (int(entry_id),))
    return True


def get_body_summary(limit=30):
    with _connect() as conn:
        profile_row = conn.execute("SELECT * FROM body_profile WHERE id=1").fetchone()
        rows = conn.execute("SELECT id,weight,logged_at FROM body_weights ORDER BY logged_at DESC,id DESC LIMIT ?", (int(limit),)).fetchall()
    entries = [dict(r) for r in rows]
    weights = [float(x["weight"]) for x in entries]
    latest = weights[0] if weights else None
    recent7 = list(reversed(weights[:7]))
    avg7 = round(sum(recent7)/len(recent7), 2) if recent7 else None
    trend = None
    if len(weights) >= 2:
        trend = round(weights[0] - weights[min(len(weights)-1, 6)], 2)
    profile = dict(profile_row) if profile_row else {}
    target = profile.get("target_weight")
    remaining = round(latest - float(target), 2) if latest is not None and target is not None else None
    return {
        "profile": {
            "target_weight": target,
            "daily_calories": profile.get("daily_calories"),
            "protein_grams": profile.get("protein_grams"),
        },
        "latest_weight": latest,
        "average_7": avg7,
        "trend_7": trend,
        "remaining": remaining,
        "entries": entries,
    }

def body_coach_context():
    data = get_body_summary(limit=14)
    p = data["profile"]
    lines = ["هدف الجسم والتغذية:"]
    lines.append(f"- الوزن الحالي: {data['latest_weight']} كجم" if data['latest_weight'] is not None else "- لا يوجد وزن مسجل بعد.")
    if p.get("target_weight") is not None: lines.append(f"- الوزن المستهدف: {p['target_weight']} كجم")
    if data.get("average_7") is not None: lines.append(f"- متوسط آخر 7 تسجيلات: {data['average_7']} كجم")
    if data.get("trend_7") is not None: lines.append(f"- تغير آخر 7 تسجيلات: {data['trend_7']:+} كجم")
    if p.get("daily_calories") is not None: lines.append(f"- هدف السعرات اليومي: {p['daily_calories']} سعرة")
    if p.get("protein_grams") is not None: lines.append(f"- هدف البروتين اليومي: {p['protein_grams']} غ")
    return "\n".join(lines)

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



def rebuild_personal_records(chat_id):
    """يعيد بناء PR من الجولات الموجودة فعليًا في sets فقط."""
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
            "SELECT id, day_key, exercise, set_number, reps, weight, logged_at "
            "FROM sets ORDER BY logged_at, id"
        ).fetchall()

        conn.execute("DELETE FROM personal_records WHERE chat_id=?", (str(chat_id),))
        state = {}
        inserted = 0

        for row in rows:
            key = (row["day_key"], row["exercise"])
            current = state.setdefault(key, {
                "max_weight": None,
                "max_reps_at_weight": {},
                "best_e1rm": None,
            })

            weight = float(row["weight"])
            reps = int(row["reps"])
            e1rm = weight * (1 + reps / 30)
            events = []

            if current["max_weight"] is None or weight > current["max_weight"]:
                events.append(f"🏆 أعلى وزن جديد: {weight:g} كجم")

            previous_reps = current["max_reps_at_weight"].get(weight)
            if previous_reps is not None and reps > previous_reps:
                events.append(f"🔥 أفضل تكرارات على {weight:g} كجم: {reps}")

            if current["best_e1rm"] is None or e1rm > current["best_e1rm"] * 1.005:
                events.append(f"💥 قوة تقديرية جديدة: {e1rm:.1f} كجم")

            created_at = row["logged_at"] or datetime.datetime.utcnow().isoformat()
            for message in events[:2]:
                conn.execute(
                    "INSERT INTO personal_records(chat_id, day_key, exercise, message, created_at) "
                    "VALUES(?,?,?,?,?)",
                    (str(chat_id), row["day_key"], row["exercise"], message, created_at),
                )
                inserted += 1

            current["max_weight"] = max(current["max_weight"] or weight, weight)
            current["max_reps_at_weight"][weight] = max(previous_reps or 0, reps)
            current["best_e1rm"] = max(current["best_e1rm"] or e1rm, e1rm)

    return {"sets_scanned": len(rows), "prs_created": inserted}


def rebuild_analytics(chat_id):
    return rebuild_personal_records(chat_id)

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
