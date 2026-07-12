"""Activity session storage and Google Health reconciliation for FitbitAir."""

from __future__ import annotations

import datetime as dt
import json
import os
import sqlite3
import uuid

DB_PATH = os.environ.get("GYM_DB_PATH", "gym_data.db")
QATAR_OFFSET = dt.timedelta(hours=3)


def _connect():
    conn = sqlite3.connect(DB_PATH, timeout=20)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def _now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_time(value):
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except Exception:
        return None


def _float(value):
    try:
        return float(value) if value is not None else None
    except Exception:
        return None


def _int(value):
    try:
        return int(round(float(value))) if value is not None else None
    except Exception:
        return None


def init_db():
    with _connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS activity_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id TEXT UNIQUE,
                google_resource_name TEXT UNIQUE,
                source TEXT NOT NULL DEFAULT 'fitbitair',
                exercise_type TEXT NOT NULL,
                display_name TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL DEFAULT 0,
                active_seconds INTEGER NOT NULL DEFAULT 0,
                distance_meters REAL,
                calories REAL,
                steps INTEGER,
                average_heart_rate INTEGER,
                maximum_heart_rate INTEGER,
                average_speed_mps REAL,
                elevation_gain_meters REAL,
                active_zone_minutes INTEGER,
                has_gps INTEGER NOT NULL DEFAULT 0,
                route_json TEXT,
                notes TEXT,
                rpe INTEGER,
                sync_status TEXT NOT NULL DEFAULT 'local_only',
                sync_error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        columns = {row[1] for row in conn.execute("PRAGMA table_info(activity_sessions)").fetchall()}
        if "deleted_at" not in columns:
            conn.execute("ALTER TABLE activity_sessions ADD COLUMN deleted_at TEXT")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_activity_start ON activity_sessions(start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_activity_type ON activity_sessions(exercise_type,start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_activity_deleted ON activity_sessions(deleted_at)")


def _validate_payload(payload):
    exercise_type = str(payload.get("exercise_type") or "OTHER").strip().upper()
    display_name = " ".join(str(payload.get("display_name") or exercise_type).strip().split())[:120]
    start = _parse_time(payload.get("start_time"))
    end = _parse_time(payload.get("end_time"))
    if not start or not end or end <= start:
        raise ValueError("وقت بداية أو نهاية النشاط غير صالح")
    duration = max(1, int(payload.get("duration_seconds") or (end - start).total_seconds()))
    active = max(1, min(duration, int(payload.get("active_seconds") or duration)))
    rpe = payload.get("rpe")
    if rpe is not None:
        rpe = max(1, min(10, int(rpe)))
    route = payload.get("route") or []
    if not isinstance(route, list):
        route = []
    route = route[:2500]
    return {
        "client_id": str(payload.get("client_id") or uuid.uuid4()),
        "source": str(payload.get("source") or "fitbitair")[:40],
        "exercise_type": exercise_type[:80],
        "display_name": display_name,
        "start_time": start.isoformat().replace("+00:00", "Z"),
        "end_time": end.isoformat().replace("+00:00", "Z"),
        "duration_seconds": duration,
        "active_seconds": active,
        "distance_meters": max(0.0, _float(payload.get("distance_meters")) or 0.0),
        "calories": max(0.0, _float(payload.get("calories")) or 0.0) or None,
        "steps": max(0, _int(payload.get("steps")) or 0) or None,
        "average_heart_rate": _int(payload.get("average_heart_rate")),
        "maximum_heart_rate": _int(payload.get("maximum_heart_rate")),
        "average_speed_mps": max(0.0, _float(payload.get("average_speed_mps")) or 0.0) or None,
        "elevation_gain_meters": max(0.0, _float(payload.get("elevation_gain_meters")) or 0.0) or None,
        "active_zone_minutes": max(0, _int(payload.get("active_zone_minutes")) or 0) or None,
        "has_gps": 1 if payload.get("has_gps") or route else 0,
        "route_json": json.dumps(route, ensure_ascii=False, separators=(",", ":")) if route else None,
        "notes": str(payload.get("notes") or "")[:1000] or None,
        "rpe": rpe,
    }


def save_local_session(payload):
    data = _validate_payload(payload)
    now = _now_iso()
    with _connect() as conn:
        conn.execute("""
            INSERT INTO activity_sessions(
                client_id,source,exercise_type,display_name,start_time,end_time,
                duration_seconds,active_seconds,distance_meters,calories,steps,
                average_heart_rate,maximum_heart_rate,average_speed_mps,elevation_gain_meters,
                active_zone_minutes,has_gps,route_json,notes,rpe,sync_status,created_at,updated_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(client_id) DO UPDATE SET
                exercise_type=excluded.exercise_type,display_name=excluded.display_name,
                start_time=excluded.start_time,end_time=excluded.end_time,
                duration_seconds=excluded.duration_seconds,active_seconds=excluded.active_seconds,
                distance_meters=excluded.distance_meters,calories=COALESCE(excluded.calories,activity_sessions.calories),
                steps=COALESCE(excluded.steps,activity_sessions.steps),
                average_heart_rate=COALESCE(excluded.average_heart_rate,activity_sessions.average_heart_rate),
                maximum_heart_rate=COALESCE(excluded.maximum_heart_rate,activity_sessions.maximum_heart_rate),
                average_speed_mps=COALESCE(excluded.average_speed_mps,activity_sessions.average_speed_mps),
                elevation_gain_meters=COALESCE(excluded.elevation_gain_meters,activity_sessions.elevation_gain_meters),
                active_zone_minutes=COALESCE(excluded.active_zone_minutes,activity_sessions.active_zone_minutes),
                has_gps=excluded.has_gps,route_json=COALESCE(excluded.route_json,activity_sessions.route_json),
                notes=excluded.notes,rpe=excluded.rpe,updated_at=excluded.updated_at
        """, (
            data["client_id"], data["source"], data["exercise_type"], data["display_name"],
            data["start_time"], data["end_time"], data["duration_seconds"], data["active_seconds"],
            data["distance_meters"], data["calories"], data["steps"], data["average_heart_rate"],
            data["maximum_heart_rate"], data["average_speed_mps"], data["elevation_gain_meters"],
            data["active_zone_minutes"], data["has_gps"], data["route_json"], data["notes"], data["rpe"],
            "local_only", now, now,
        ))
        row = conn.execute("SELECT * FROM activity_sessions WHERE client_id=?", (data["client_id"],)).fetchone()
    return _row(row)


def mark_google_sync(session_id, status, resource_name=None, error=None):
    with _connect() as conn:
        conn.execute(
            "UPDATE activity_sessions SET sync_status=?,google_resource_name=COALESCE(?,google_resource_name),sync_error=?,updated_at=? WHERE id=?",
            (status, resource_name, str(error)[:600] if error else None, _now_iso(), int(session_id)),
        )
        row = conn.execute("SELECT * FROM activity_sessions WHERE id=?", (int(session_id),)).fetchone()
    return _row(row)


def _row(row):
    if not row:
        return None
    item = dict(row)
    item["has_gps"] = bool(item.get("has_gps"))
    item.pop("route_json", None)
    return item


def get_session(session_id):
    with _connect() as conn:
        row = conn.execute("SELECT * FROM activity_sessions WHERE id=?", (int(session_id),)).fetchone()
    return _row(row)


def delete_session(session_id):
    """Soft-delete one activity so Google imports do not recreate it."""
    with _connect() as conn:
        row = conn.execute("SELECT * FROM activity_sessions WHERE id=?", (int(session_id),)).fetchone()
        if not row:
            return None
        conn.execute(
            "UPDATE activity_sessions SET deleted_at=?, sync_status='deleted', updated_at=? WHERE id=?",
            (_now_iso(), _now_iso(), int(session_id)),
        )
    return _row(row)


def list_sessions(days=30, limit=100):
    days = max(1, min(365, int(days)))
    limit = max(1, min(500, int(limit)))
    cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)).isoformat().replace("+00:00", "Z")
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM activity_sessions WHERE start_time>=? AND deleted_at IS NULL ORDER BY start_time DESC LIMIT ?",
            (cutoff, limit),
        ).fetchall()
    return [_row(r) for r in rows]


def summary(days=7):
    rows = list_sessions(days=days, limit=500)
    return {
        "days": int(days),
        "sessions": len(rows),
        "active_seconds": sum(int(x.get("active_seconds") or 0) for x in rows),
        "distance_meters": round(sum(float(x.get("distance_meters") or 0) for x in rows), 1),
        "calories": round(sum(float(x.get("calories") or 0) for x in rows), 1),
        "types": sorted({x.get("exercise_type") for x in rows if x.get("exercise_type")}),
    }


def _canonical_type(exercise_type):
    value = str(exercise_type or "OTHER").upper()
    groups = {
        "RUNNING": {"RUNNING", "TRAIL_RUN", "INCLINE_RUN", "TREADMILL"},
        "WALKING": {"WALKING", "POWER_WALKING", "NORDIC_WALKING", "STROLLER_WALK", "WALK_WITH_WEIGHTS", "INCLINE_WALK", "TREADMILL_WALK"},
        "BIKING": {"BIKING", "OUTDOOR_BIKE", "MOUNTAIN_BIKE", "ELECTRIC_BIKE", "HAND_CYCLING", "STATIONARY_BIKE", "SPINNING", "ASSAULT_BIKE"},
        "SWIMMING": {"SWIMMING", "SWIMMING_OPEN_WATER", "SWIMMING_POOL", "SYNCHRONIZED_SWIMMING"},
        "ROWING": {"ROWING", "ROWING_MACHINE", "CANOEING", "KAYAKING"},
        "STRENGTH_TRAINING": {"STRENGTH_TRAINING", "FUNCTIONAL_STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHTS", "WEIGHT_MACHINES", "FREE_WEIGHTS", "POWERLIFTING", "BODY_WEIGHT", "CALISTHENICS"},
        "CARDIO_WORKOUT": {"CARDIO_WORKOUT", "AEROBIC_WORKOUT", "HIIT", "INTERVAL_WORKOUT", "TABATA_WORKOUT", "CIRCUIT_TRAINING", "CROSSFIT", "BOOTCAMP"},
    }
    for canonical, members in groups.items():
        if value in members:
            return canonical
    return value


def _find_match(conn, exercise_type, start_time, end_time):
    start = _parse_time(start_time)
    end = _parse_time(end_time)
    if not start or not end:
        return None
    window_start = (start - dt.timedelta(minutes=8)).isoformat().replace("+00:00", "Z")
    window_end = (start + dt.timedelta(minutes=8)).isoformat().replace("+00:00", "Z")
    rows = conn.execute(
        "SELECT * FROM activity_sessions WHERE start_time BETWEEN ? AND ? ORDER BY ABS(duration_seconds-?) ASC",
        (window_start, window_end, max(1, int((end - start).total_seconds()))),
    ).fetchall()
    for row in rows:
        same_type = (
            _canonical_type(row["exercise_type"]) == _canonical_type(exercise_type)
            or row["exercise_type"] in {"OTHER", "WORKOUT"}
        )
        duration_delta = abs(int(row["duration_seconds"] or 0) - int((end - start).total_seconds()))
        if same_type and duration_delta <= max(300, int((end - start).total_seconds() * 0.25)):
            return row
    return None


def import_google_exercises(points):
    imported = 0
    merged = 0
    now = _now_iso()
    with _connect() as conn:
        for point in points or []:
            exercise = point.get("exercise") or point.get("data", {}).get("exercise") or {}
            if not isinstance(exercise, dict):
                continue
            interval = exercise.get("interval") or {}
            start = interval.get("startTime") or interval.get("start_time")
            end = interval.get("endTime") or interval.get("end_time")
            if not start or not end:
                continue
            exercise_type = str(exercise.get("exerciseType") or exercise.get("exercise_type") or "OTHER")
            metrics = exercise.get("metricsSummary") or exercise.get("metrics_summary") or {}
            resource_name = point.get("name") or point.get("dataPointName") or point.get("resourceName") or point.get("resource_name")
            active_duration = exercise.get("activeDuration") or ""
            active_seconds = None
            if isinstance(active_duration, str) and active_duration.endswith("s"):
                try:
                    active_seconds = int(float(active_duration[:-1]))
                except Exception:
                    pass
            start_dt = _parse_time(start); end_dt = _parse_time(end)
            duration = max(1, int((end_dt - start_dt).total_seconds())) if start_dt and end_dt else 1
            payload = {
                "source": "google_health",
                "exercise_type": exercise_type,
                "display_name": exercise.get("displayName") or exercise_type.replace("_", " ").title(),
                "start_time": start,
                "end_time": end,
                "duration_seconds": duration,
                "active_seconds": active_seconds or duration,
                "distance_meters": (_float(metrics.get("distanceMillimeters")) or 0) / 1000,
                "calories": _float(metrics.get("caloriesKcal")),
                "steps": _int(metrics.get("steps")),
                "average_heart_rate": _int(metrics.get("averageHeartRateBeatsPerMinute")),
                "average_speed_mps": (_float(metrics.get("averageSpeedMillimetersPerSecond")) or 0) / 1000 or None,
                "elevation_gain_meters": (_float(metrics.get("elevationGainMillimeters")) or 0) / 1000 or None,
                "active_zone_minutes": _int(metrics.get("activeZoneMinutes")),
                "has_gps": bool((exercise.get("exerciseMetadata") or {}).get("hasGps")),
                "notes": exercise.get("notes") or None,
            }
            match = _find_match(conn, exercise_type, start, end)
            if match:
                conn.execute("""
                    UPDATE activity_sessions SET
                        source='fitbitair+google_health',google_resource_name=COALESCE(?,google_resource_name),
                        display_name=COALESCE(NULLIF(?,''),display_name),
                        calories=COALESCE(?,calories),steps=COALESCE(?,steps),
                        average_heart_rate=COALESCE(?,average_heart_rate),
                        average_speed_mps=COALESCE(?,average_speed_mps),
                        elevation_gain_meters=COALESCE(?,elevation_gain_meters),
                        active_zone_minutes=COALESCE(?,active_zone_minutes),
                        has_gps=MAX(has_gps,?),sync_status='synced',sync_error=NULL,updated_at=?
                    WHERE id=?
                """, (
                    resource_name, payload["display_name"], payload["calories"], payload["steps"],
                    payload["average_heart_rate"], payload["average_speed_mps"], payload["elevation_gain_meters"],
                    payload["active_zone_minutes"], 1 if payload["has_gps"] else 0, now, match["id"],
                ))
                merged += 1
                continue
            if resource_name:
                exists = conn.execute("SELECT 1 FROM activity_sessions WHERE google_resource_name=?", (resource_name,)).fetchone()
                if exists:
                    continue
            client_id = "google_" + (str(resource_name or uuid.uuid4()).replace("/", "_")[-120:])
            conn.execute("""
                INSERT OR IGNORE INTO activity_sessions(
                    client_id,google_resource_name,source,exercise_type,display_name,start_time,end_time,
                    duration_seconds,active_seconds,distance_meters,calories,steps,average_heart_rate,
                    average_speed_mps,elevation_gain_meters,active_zone_minutes,has_gps,notes,
                    sync_status,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                client_id, resource_name, "google_health", exercise_type, payload["display_name"],
                _parse_time(start).isoformat().replace("+00:00", "Z"), _parse_time(end).isoformat().replace("+00:00", "Z"),
                duration, payload["active_seconds"], payload["distance_meters"], payload["calories"], payload["steps"],
                payload["average_heart_rate"], payload["average_speed_mps"], payload["elevation_gain_meters"],
                payload["active_zone_minutes"], 1 if payload["has_gps"] else 0, payload["notes"], "synced", now, now,
            ))
            imported += 1
    return {"imported": imported, "merged": merged}


def coach_context(days=14):
    rows = list_sessions(days=days, limit=30)
    if not rows:
        return "🏃 النشاطات الهوائية والرياضية: لا توجد جلسات مسجلة مؤخرًا."
    lines = [f"🏃 النشاطات الهوائية والرياضية — آخر {days} يوم:"]
    for item in rows[:12]:
        minutes = round((item.get("active_seconds") or item.get("duration_seconds") or 0) / 60)
        distance = float(item.get("distance_meters") or 0) / 1000
        bits = [f"{item.get('start_time','')[:10]}: {item.get('display_name') or item.get('exercise_type')}، {minutes} دقيقة"]
        if distance > 0.05:
            bits.append(f"{distance:.2f} كم")
        if item.get("calories"):
            bits.append(f"{float(item['calories']):.0f} سعرة")
        if item.get("average_heart_rate"):
            bits.append(f"متوسط نبض {item['average_heart_rate']}")
        lines.append(" • ".join(bits))
    return "\n".join(lines)


init_db()
