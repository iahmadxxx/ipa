"""
google_health_client.py — النسخة المطورة
جديد: كل دالة تقبل تاريخ محدد، + get_summary_by_date للإحصائيات التاريخية.
"""

import os
import time
import requests
import re

import token_store
from datetime import datetime, timedelta, timezone, date as date_type
from zoneinfo import ZoneInfo

TOKEN_URL = "https://oauth2.googleapis.com/token"
API_BASE = "https://health.googleapis.com/v4/users/me/dataTypes"

LOCAL_UTC_OFFSET_HOURS = 3
REQUEST_TIMEOUT = 12
MAX_PAGES = 3

_token_cache = {"access_token": None, "expires_at": 0}


class GoogleHealthError(Exception):
    pass


class TokenExpiredError(GoogleHealthError):
    """التوكن انتهى نهائيًا ويحتاج إعادة موافقة (/reauth)."""
    pass


def get_access_token():
    now = time.time()
    if _token_cache["access_token"] and now < _token_cache["expires_at"]:
        return _token_cache["access_token"]

    client_id = os.environ.get("GOOGLE_CLIENT_ID")
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET")
    refresh_token = token_store.get_refresh_token()

    if not all([client_id, client_secret, refresh_token]):
        raise GoogleHealthError("أسرار Google ناقصة (تحقق من env_config.py).")

    resp = requests.post(TOKEN_URL, data={
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }, timeout=REQUEST_TIMEOUT)

    if resp.status_code != 200:
        body = resp.text[:200]
        if "invalid_grant" in body:
            raise TokenExpiredError(
                "توكن Google انتهى (الوضع Testing = صلاحية 7 أيام)."
            )
        raise GoogleHealthError(
            f"فشل تجديد access token ({resp.status_code}): {body}"
        )
    data = resp.json()
    token = data["access_token"]
    expires_in = data.get("expires_in", 3000)
    _token_cache["access_token"] = token
    _token_cache["expires_at"] = now + expires_in - 60
    return token


def _headers():
    return {
        "Authorization": f"Bearer {get_access_token()}",
        "Accept": "application/json",
    }


def _daily_rollup(data_type_kebab, d):
    url = f"{API_BASE}/{data_type_kebab}/dataPoints:dailyRollUp"
    body = {
        "range": {
            "start": {"date": {"year": d.year, "month": d.month, "day": d.day}},
            "end": {"date": {"year": d.year, "month": d.month, "day": d.day},
                    "time": {"hours": 23, "minutes": 59, "seconds": 59}},
        },
        "windowSizeDays": 1,
    }
    resp = requests.post(url, headers=_headers(), json=body, timeout=REQUEST_TIMEOUT)
    if resp.status_code != 200:
        raise GoogleHealthError(f"{data_type_kebab}: {resp.status_code} {resp.text[:200]}")
    points = resp.json().get("rollupDataPoints", [])
    return points[0] if points else None


def _list_points(data_type_kebab, filter_expr, max_pages=MAX_PAGES):
    url = f"{API_BASE}/{data_type_kebab}/dataPoints"
    all_points, page_token = [], None
    pages_fetched = 0
    while True:
        params = {"pageSize": 200}
        if filter_expr:
            params["filter"] = filter_expr
        if page_token:
            params["pageToken"] = page_token
        resp = requests.get(url, headers=_headers(), params=params, timeout=REQUEST_TIMEOUT)
        if resp.status_code != 200:
            raise GoogleHealthError(f"{data_type_kebab}: {resp.status_code} {resp.text[:200]}")
        body = resp.json()
        all_points.extend(body.get("dataPoints", []))
        page_token = body.get("nextPageToken")
        pages_fetched += 1
        if not page_token or pages_fetched >= max_pages:
            break
    return all_points


def _utc_now():
    return datetime.now(timezone.utc)


def _parse_time_local(iso_string):
    if not iso_string:
        return None
    try:
        s = iso_string.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt + timedelta(hours=LOCAL_UTC_OFFSET_HOURS)
    except (ValueError, TypeError):
        return None


QATAR_TZ = ZoneInfo("Asia/Qatar")


def _sleep_timestamp_has_explicit_zone(raw):
    text = str(raw or "").strip()
    if not text:
        return False
    if text.endswith(("Z", "z")):
        return True
    return bool(re.search(r"[+-]\d{2}:?\d{2}$", text))


def _parse_sleep_time_smart(raw_value):
    """
    Canonical sleep timestamp parser.

    - Explicit Z/UTC/offset: parse as a real instant, then convert to Qatar.
    - No timezone/offset: preserve wall-clock fields as Qatar local time.

    Always returns a timezone-aware Asia/Qatar datetime.
    """
    if raw_value is None:
        return None

    raw = str(raw_value).strip()
    if not raw:
        return None

    try:
        if _sleep_timestamp_has_explicit_zone(raw):
            normalized = raw[:-1] + "+00:00" if raw.endswith(("Z", "z")) else raw
            dt = datetime.fromisoformat(normalized)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(QATAR_TZ)

        dt = datetime.fromisoformat(raw)
        return dt.replace(tzinfo=QATAR_TZ)

    except (ValueError, TypeError, OverflowError):
        return None


def _parse_sleep_time_exact(raw_value):
    """Legacy parser that preserves the timestamp's written wall-clock fields.

    Kept only for backward-compatible tests/tools. Production sleep parsing uses
    ``_parse_sleep_time_smart`` so explicit UTC/offset timestamps are converted
    to Qatar time correctly.
    """
    if raw_value is None:
        return None
    raw = str(raw_value).strip()
    if not raw:
        return None
    try:
        normalized = raw[:-1] + "+00:00" if raw.endswith(("Z", "z")) else raw
        dt = datetime.fromisoformat(normalized)
        return dt.replace(tzinfo=None)
    except (ValueError, TypeError, OverflowError):
        return None


def _to_date(d):
    """يحول نص أو date object إلى date."""
    if isinstance(d, str):
        return datetime.fromisoformat(d).date()
    if isinstance(d, datetime):
        return d.date()
    return d


def get_steps(d):
    return _get_steps(_to_date(d))


def _get_steps(d):
    point = _daily_rollup("steps", d)
    if not point:
        return None
    val = point.get("steps", {}).get("countSum")
    return int(val) if val is not None else None


def get_calories(d):
    return _get_calories(_to_date(d))


def _get_calories(d):
    point = _daily_rollup("total-calories", d)
    if not point:
        return None
    val = point.get("totalCalories", {}).get("kcalSum")
    return int(float(val)) if val is not None else None


def get_resting_heart_rate(d=None):
    """
    معدل نبض الراحة.

    عند طلب تاريخ:
    1) نرجع قراءة نفس اليوم إن وجدت.
    2) إذا Google لم ينشر قراءة اليوم بعد، نرجع أحدث قراءة سابقة خلال 7 أيام فقط.
    """
    points = _list_points("daily-resting-heart-rate", "")
    if not points:
        return None

    def unpack(point):
        payload = point.get("dailyRestingHeartRate", {})
        dd = payload.get("date", {})
        try:
            point_date = date_type(
                int(dd.get("year")),
                int(dd.get("month")),
                int(dd.get("day")),
            )
        except Exception:
            point_date = None

        bpm = payload.get("beatsPerMinute")
        try:
            bpm = int(round(float(bpm))) if bpm is not None else None
        except Exception:
            bpm = None

        return point_date, bpm

    parsed = [unpack(p) for p in points]
    parsed = [(dt, bpm) for dt, bpm in parsed if dt is not None and bpm is not None]
    if not parsed:
        return None

    parsed.sort(key=lambda x: x[0], reverse=True)

    if d is None:
        return parsed[0][1]

    target = _to_date(d)

    for dt, bpm in parsed:
        if dt == target:
            return bpm

    recent_previous = [
        (dt, bpm)
        for dt, bpm in parsed
        if dt < target and 0 < (target - dt).days <= 7
    ]
    if recent_previous:
        return recent_previous[0][1]

    return None


def _parse_heart_timestamp(raw_value):
    """Parse one timestamp value without looking elsewhere in the payload."""
    if raw_value is None:
        return None

    if isinstance(raw_value, dict):
        # protobuf timestamp object
        seconds = raw_value.get("seconds")
        if seconds is not None:
            try:
                return datetime.fromtimestamp(float(seconds), tz=timezone.utc)
            except Exception:
                return None
        return None

    if isinstance(raw_value, (int, float)):
        # Avoid guessing units unless magnitude is clearly milliseconds.
        value = float(raw_value)
        try:
            if abs(value) > 10_000_000_000:
                value /= 1000.0
            return datetime.fromtimestamp(value, tz=timezone.utc)
        except Exception:
            return None

    if isinstance(raw_value, str):
        raw = raw_value.strip()
        if not raw:
            return None
        try:
            # Heart-rate timestamps represent an instant. Do not add Qatar's
            # offset to the instant itself (the old parser shifted every Z
            # timestamp three hours into the future and the freshness filter
            # rejected it). Convert explicit zones to UTC; when Google omits a
            # zone, treat the written wall-clock value as Qatar local time.
            normalized = raw[:-1] + "+00:00" if raw.endswith(("Z", "z")) else raw
            dt = datetime.fromisoformat(normalized)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=QATAR_TZ)
            return dt.astimezone(timezone.utc)
        except Exception:
            return None

    return None


def _direct_bpm_from_node(node):
    """Read BPM only from this dictionary itself, never from siblings/children."""
    if not isinstance(node, dict):
        return None

    for key in (
        "beatsPerMinute", "beats_per_minute", "bpm",
        "value", "doubleValue", "intVal", "integerValue",
    ):
        value = node.get(key)
        if isinstance(value, (int, float, str)):
            try:
                bpm = int(round(float(value)))
                if 20 <= bpm <= 260:
                    return bpm
            except (TypeError, ValueError):
                pass

    return None


def _direct_time_from_node(node):
    """
    Read timestamp only from this sample node or its own interval metadata.
    Never search unrelated sibling samples.
    """
    if not isinstance(node, dict):
        return None

    interval = node.get("interval") or node.get("timeInterval") or {}
    if not isinstance(interval, dict):
        interval = {}

    # Some Google Health payloads keep the interval under metadata/timing while
    # the BPM remains on this exact sample. Looking only inside this same node is
    # still strict pairing and never borrows a timestamp from a sibling sample.
    metadata = node.get("metadata") or {}
    if isinstance(metadata, dict):
        timing = metadata.get("timing") or metadata.get("time") or metadata
        if isinstance(timing, dict):
            nested_interval = timing.get("interval") or timing.get("timeInterval") or {}
            if isinstance(nested_interval, dict) and nested_interval:
                interval = {**nested_interval, **interval}

    # String/ISO timestamps.
    for key in (
        "endTime", "end_time", "startTime", "start_time",
        "dateTime", "datetime", "timestamp", "time",
    ):
        if key in node:
            parsed = _parse_heart_timestamp(node.get(key))
            if parsed is not None:
                return parsed

        if key in interval:
            parsed = _parse_heart_timestamp(interval.get(key))
            if parsed is not None:
                return parsed

    # Explicit epoch fields.
    for key in ("timestampMillis", "epochMillis", "timeMillis"):
        if key in node:
            try:
                return datetime.fromtimestamp(float(node[key]) / 1000.0, tz=timezone.utc)
            except Exception:
                pass

    for key in ("timestampSeconds", "epochSeconds", "unixTime"):
        if key in node:
            parsed = _parse_heart_timestamp(node.get(key))
            if parsed is not None:
                return parsed

    # Protobuf-style timestamp object stored under a timestamp key.
    for key in ("timestamp", "dateTime", "time"):
        value = node.get(key)
        if isinstance(value, dict):
            parsed = _parse_heart_timestamp(value)
            if parsed is not None:
                return parsed

    return None


def _collect_paired_heart_samples(node):
    """
    Collect only BPM/time pairs that belong to the SAME logical sample.

    Important:
    - A BPM from one sample is never paired with a timestamp from another sample.
    - Parent containers may pair a direct BPM with their own interval metadata.
    - Child samples are processed independently.
    """
    pairs = []

    if isinstance(node, dict):
        bpm = _direct_bpm_from_node(node)
        measured_at = _direct_time_from_node(node)

        if bpm is not None and measured_at is not None:
            pairs.append((bpm, measured_at))

        # Recurse into each child independently.
        for value in node.values():
            if isinstance(value, (dict, list)):
                pairs.extend(_collect_paired_heart_samples(value))

    elif isinstance(node, list):
        for item in node:
            pairs.extend(_collect_paired_heart_samples(item))

    return pairs


def _extract_heart_sample(point):
    """
    Return the newest strict pair from one Google Health data point.

    A result exists only when BPM and timestamp are proven to come from the
    same logical sample/container.
    """
    payload = point.get("heartRate") or point.get("heart_rate") or point
    pairs = _collect_paired_heart_samples(payload)

    # Some Google Health responses keep the interval on the outer data point
    # and the BPM inside one nested value. Pairing is still safe when the whole
    # data point contains one unique plausible BPM value.
    if not pairs and isinstance(payload, dict):
        outer_time = _direct_time_from_node(point) or _direct_time_from_node(payload)

        def collect_bpms(node):
            found = []
            if isinstance(node, dict):
                value = _direct_bpm_from_node(node)
                if value is not None:
                    found.append(value)
                for child in node.values():
                    if isinstance(child, (dict, list)):
                        found.extend(collect_bpms(child))
            elif isinstance(node, list):
                for child in node:
                    found.extend(collect_bpms(child))
            return found

        unique_bpms = sorted(set(collect_bpms(payload)))
        if outer_time is not None and len(unique_bpms) == 1:
            pairs.append((unique_bpms[0], outer_time))

    if not pairs:
        return None

    # Deduplicate exact pairs and select newest time.
    unique = {}
    for bpm, measured_at in pairs:
        unique[(bpm, measured_at.isoformat())] = (bpm, measured_at)

    return max(unique.values(), key=lambda item: item[1])


def get_current_heart_rate():
    """
    أحدث قراءة نبض موثقة فقط.

    شروط القبول:
    - BPM ووقت القياس من نفس العينة.
    - وقت القياس ليس في المستقبل بأكثر من 5 دقائق.
    - القراءة ليست أقدم من 72 ساعة.
    """
    now = _utc_now()
    windows = [timedelta(hours=6), timedelta(hours=24), timedelta(days=3)]
    all_points = []
    last_err = None

    for window in windows:
        start = (now - window).strftime("%Y-%m-%dT%H:%M:%SZ")
        filters = [
            f'heart_rate.interval.start_time >= "{start}"',
            f'heartRate.interval.startTime >= "{start}"',
            f'interval.start_time >= "{start}"',
            "",
        ]

        for flt in filters:
            try:
                points = _list_points("heart-rate", flt, max_pages=3)
                if points:
                    all_points = points
                    break
            except GoogleHealthError as exc:
                last_err = exc

        if all_points:
            break

    if not all_points:
        if last_err:
            raise last_err
        return None

    samples = []
    for point in all_points:
        sample = _extract_heart_sample(point)
        if sample is None:
            continue

        bpm, measured_at = sample

        # Normalize timezone-aware timestamp to UTC for reliable comparison.
        if measured_at.tzinfo is None:
            measured_at = measured_at.replace(tzinfo=timezone.utc)

        age_seconds = (now - measured_at.astimezone(timezone.utc)).total_seconds()

        if age_seconds < -300:
            continue
        if age_seconds > 72 * 3600:
            continue

        samples.append((bpm, measured_at))

    if not samples:
        return None

    return max(samples, key=lambda item: item[1])


def get_sleep(d=None):
    """
    جلسة نوم لتاريخ محدد أو آخر 48 ساعة.
    النوم الليلي (نام ليلة X وصحا صبح X+1) يظهر تحت تاريخ X+1.
    """
    if d is None:
        start_utc = _utc_now() - timedelta(hours=48)
    else:
        target = _to_date(d)
        # نبدأ البحث من مساء اليوم السابق (نوم ليلي يبدأ قبل منتصف الليل)
        start_utc = datetime(target.year, target.month, target.day,
                             tzinfo=timezone.utc) - timedelta(hours=20)

    filter_expr = f'sleep.interval.end_time >= "{start_utc.strftime("%Y-%m-%dT%H:%M:%SZ")}"'
    points = _list_points("sleep", filter_expr)
    if not points:
        return None

    # لو تاريخ محدد: نأخذ الجلسة اللي نهت في ذلك اليوم أو صبيحته (بالتوقيت المحلي)
    if d is not None:
        target = _to_date(d)
        end_limit_utc = (datetime(target.year, target.month, target.day, tzinfo=timezone.utc)
                         + timedelta(hours=30))
        end_limit_str = end_limit_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        points = [p for p in points
                  if p.get("sleep", {}).get("interval", {}).get("endTime", "") <= end_limit_str]
        if not points:
            return None

    points.sort(
        key=lambda p: p.get("sleep", {}).get("interval", {}).get("endTime", ""),
        reverse=True,
    )
    sleep = points[0]["sleep"]

    raw_stages = (sleep.get("stages") or sleep.get("sleepStages")
                  or sleep.get("stageIntervals") or [])
    timeline = []
    for st in raw_stages:
        interval = st.get("interval", st)
        start_dt = _parse_sleep_time_smart(interval.get("startTime"))
        end_dt = _parse_sleep_time_smart(interval.get("endTime"))
        stype = st.get("type") or st.get("stage") or st.get("stageType")
        minutes = None
        duration_seconds = None
        if start_dt and end_dt:
            duration_seconds = max(0, int(round((end_dt - start_dt).total_seconds())))
            minutes = int((duration_seconds + 30) // 60)
        timeline.append({
            "type": stype,
            "start": start_dt,
            "end": end_dt,
            "minutes": minutes,
            "duration_seconds": duration_seconds,
        })
    sleep["_stages_timeline"] = timeline

    interval = sleep.get("interval", {})
    sleep["_local_start"] = _parse_sleep_time_smart(interval.get("startTime"))
    sleep["_local_end"] = _parse_sleep_time_smart(interval.get("endTime"))

    return sleep


def get_summary_by_date(date_str):
    """يجيب ملخص كامل (خطوات، سعرات، نبض، نوم) لتاريخ محدد."""
    d = _to_date(date_str)
    result = {"date": d.isoformat()}
    for key, fn in [
        ("steps", lambda: _get_steps(d)),
        ("calories", lambda: _get_calories(d)),
        ("heart_rate", lambda: get_resting_heart_rate(d)),
        ("sleep", lambda: get_sleep(d)),
    ]:
        try:
            result[key] = fn()
        except GoogleHealthError as e:
            result[key] = None
            result[f"{key}_error"] = str(e)
    # النبض اللحظي فقط لليوم الحالي
    today = (_utc_now() + timedelta(hours=LOCAL_UTC_OFFSET_HOURS)).date()
    if d == today:
        try:
            result["current_hr"] = get_current_heart_rate()
        except GoogleHealthError:
            result["current_hr"] = None
    else:
        result["current_hr"] = None
    return result


def get_today_summary():
    return get_summary_by_date((_utc_now() + timedelta(hours=LOCAL_UTC_OFFSET_HOURS)).date().isoformat())


def get_week_summary_for(end_date=None):
    """ملخص 7 أيام تنتهي في end_date. كل استدعاء يجلب البيانات من Google Health مباشرة."""
    if end_date is None:
        end = (_utc_now() + timedelta(hours=LOCAL_UTC_OFFSET_HOURS)).date()
    else:
        end = _to_date(end_date)
    days = []
    for i in range(6, -1, -1):
        d = end - timedelta(days=i)
        entry = {"date": d.isoformat()}
        try:
            entry["steps"] = _get_steps(d)
        except GoogleHealthError:
            entry["steps"] = None
        try:
            entry["calories"] = _get_calories(d)
        except GoogleHealthError:
            entry["calories"] = None
        days.append(entry)
    return days


def get_week_summary():
    return get_week_summary_for()


def get_paired_devices():
    """قائمة الأجهزة المقترنة مع البطارية ووقت آخر مزامنة."""
    url = "https://health.googleapis.com/v4/users/me/pairedDevices"
    resp = requests.get(
        url,
        headers=_headers(),
        params={"pageSize": 100},
        timeout=REQUEST_TIMEOUT,
    )
    if resp.status_code != 200:
        raise GoogleHealthError(
            f"paired-devices: {resp.status_code} {resp.text[:300]}"
        )
    return resp.json().get("pairedDevices", [])

# ---------------------------------------------------------------------------
# Exercise sessions (FitbitAir activity tracking)
# ---------------------------------------------------------------------------

def _exercise_time_filter(start_time=None, end_time=None):
    """Build a supported exercise-session filter.

    Google Health supports civil start-time filters for exercise sessions, not
    physical ``exercise.interval.start_time`` filters.  Add a one-day buffer on
    both sides so activities recorded while travelling are not missed because
    their civil timezone differs from the server timezone.  Exact matching and
    de-duplication are still performed locally after download.
    """
    parts = []
    if start_time:
        try:
            start = datetime.fromisoformat(str(start_time).replace("Z", "+00:00"))
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone.utc)
        except Exception:
            start = None
        if start:
            civil_start = (start - timedelta(days=1)).date().isoformat()
            parts.append(f'exercise.interval.civil_start_time >= "{civil_start}"')
    if end_time:
        try:
            end = datetime.fromisoformat(str(end_time).replace("Z", "+00:00"))
            if end.tzinfo is None:
                end = end.replace(tzinfo=timezone.utc)
        except Exception:
            end = None
        if end:
            civil_end = (end + timedelta(days=1)).date().isoformat()
            parts.append(f'exercise.interval.civil_start_time < "{civil_end}"')
    return " AND ".join(parts)


def list_exercises(start_time=None, end_time=None, reconcile=True, max_pages=8):
    """List exercise sessions from Google Health, preferring reconciled Fitbit data."""
    endpoint = "dataPoints:reconcile" if reconcile else "dataPoints"
    url = f"{API_BASE}/exercise/{endpoint}"
    filter_expr = _exercise_time_filter(start_time, end_time)
    all_points = []
    page_token = None
    pages = 0
    while True:
        params = {"pageSize": 25}
        if filter_expr:
            params["filter"] = filter_expr
        if page_token:
            params["pageToken"] = page_token
        if reconcile:
            params["dataSourceFamily"] = "users/me/dataSourceFamilies/all-sources"
        resp = requests.get(url, headers=_headers(), params=params, timeout=REQUEST_TIMEOUT)
        if resp.status_code != 200:
            # Some accounts temporarily reject reconcile filters. Fall back to list.
            if reconcile and pages == 0:
                return list_exercises(start_time, end_time, reconcile=False, max_pages=max_pages)
            raise GoogleHealthError(f"exercise: {resp.status_code} {resp.text[:400]}")
        body = resp.json()
        all_points.extend(body.get("dataPoints", []))
        page_token = body.get("nextPageToken")
        pages += 1
        if not page_token or pages >= max_pages:
            break
    return all_points


def create_exercise_session(session):
    """Create one exercise session written by FitbitAir in Google Health."""
    start = session.get("start_time")
    end = session.get("end_time")
    if not start or not end:
        raise GoogleHealthError("exercise create: missing start/end")

    metrics = {}
    distance_m = session.get("distance_meters")
    if distance_m is not None and float(distance_m) > 0:
        metrics["distanceMillimeters"] = float(distance_m) * 1000.0
    calories = session.get("calories")
    if calories is not None and float(calories) > 0:
        metrics["caloriesKcal"] = float(calories)
    steps = session.get("steps")
    if steps is not None and int(steps) > 0:
        metrics["steps"] = str(int(steps))
    avg_hr = session.get("average_heart_rate")
    if avg_hr is not None and int(avg_hr) > 0:
        metrics["averageHeartRateBeatsPerMinute"] = str(int(avg_hr))
    speed = session.get("average_speed_mps")
    if speed is not None and float(speed) > 0:
        metrics["averageSpeedMillimetersPerSecond"] = float(speed) * 1000.0
    elevation = session.get("elevation_gain_meters")
    if elevation is not None and float(elevation) > 0:
        metrics["elevationGainMillimeters"] = float(elevation) * 1000.0
    azm = session.get("active_zone_minutes")
    if azm is not None and int(azm) > 0:
        metrics["activeZoneMinutes"] = str(int(azm))

    active_seconds = max(1, int(session.get("active_seconds") or session.get("duration_seconds") or 1))
    offset_seconds = int(session.get("utc_offset_seconds") or LOCAL_UTC_OFFSET_HOURS * 3600)
    offset = f"{offset_seconds}s"
    exercise = {
        "interval": {
            "startTime": start,
            "startUtcOffset": offset,
            "endTime": end,
            "endUtcOffset": offset,
        },
        "exerciseType": str(session.get("exercise_type") or "OTHER"),
        "displayName": str(session.get("display_name") or "FitbitAir Activity")[:120],
        "activeDuration": f"{active_seconds}s",
        "metricsSummary": metrics,
        "exerciseMetadata": {"hasGps": bool(session.get("has_gps"))},
        "exerciseEvents": [
            {"eventTime": start, "eventUtcOffset": offset, "exerciseEventType": "START"},
            {"eventTime": end, "eventUtcOffset": offset, "exerciseEventType": "STOP"},
        ],
    }
    notes = str(session.get("notes") or "").strip()
    client_id = str(session.get("client_id") or "").strip()
    marker = f"FitbitAir:{client_id}" if client_id else "FitbitAir"
    exercise["notes"] = (notes + "\n" + marker).strip()[:1000]

    resp = requests.post(
        f"{API_BASE}/exercise/dataPoints",
        headers={**_headers(), "Content-Type": "application/json"},
        json={"exercise": exercise},
        timeout=REQUEST_TIMEOUT,
    )
    if resp.status_code not in (200, 201, 202):
        raise GoogleHealthError(f"exercise create: {resp.status_code} {resp.text[:500]}")
    return resp.json()
