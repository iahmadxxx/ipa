"""
google_health_client.py — النسخة المطورة
جديد: كل دالة تقبل تاريخ محدد، + get_summary_by_date للإحصائيات التاريخية.
"""

import os
import time
import requests

import token_store
from datetime import datetime, timedelta, timezone, date as date_type

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
    """معدل النبض أثناء الراحة — لتاريخ محدد أو آخر قراءة."""
    points = _list_points("daily-resting-heart-rate", "")
    if not points:
        return None

    def point_date(p):
        dd = p.get("dailyRestingHeartRate", {}).get("date", {})
        return (dd.get("year", 0), dd.get("month", 0), dd.get("day", 0))

    if d is not None:
        target = _to_date(d)
        # نفلتر للنقطة المطابقة للتاريخ
        for p in points:
            dd = p.get("dailyRestingHeartRate", {}).get("date", {})
            if (dd.get("year") == target.year
                    and dd.get("month") == target.month
                    and dd.get("day") == target.day):
                bpm = p["dailyRestingHeartRate"].get("beatsPerMinute")
                return int(bpm) if bpm is not None else None
        return None

    points.sort(key=point_date, reverse=True)
    latest = points[0].get("dailyRestingHeartRate", {})
    bpm = latest.get("beatsPerMinute")
    return int(bpm) if bpm is not None else None


def _extract_heart_sample(point):
    """يحاول قراءة قيمة النبض والوقت من أكثر صيغ Google Health شيوعًا."""
    payload = point.get("heartRate") or point.get("heart_rate") or point

    def pick_number(obj):
        if isinstance(obj, dict):
            for key in ("beatsPerMinute", "beats_per_minute", "bpm", "value", "doubleValue", "intVal"):
                val = obj.get(key)
                if isinstance(val, (int, float, str)):
                    try:
                        return float(val)
                    except (TypeError, ValueError):
                        pass
            for key in ("samples", "values", "measurements", "data"):
                seq = obj.get(key)
                if isinstance(seq, list):
                    found = [pick_number(x) for x in seq]
                    found = [x for x in found if x is not None]
                    if found:
                        return found[-1]
        elif isinstance(obj, (int, float)):
            return float(obj)
        return None

    def pick_time(obj):
        if not isinstance(obj, dict):
            return None
        interval = obj.get("interval") or obj.get("timeInterval") or {}
        for key in ("endTime", "end_time", "startTime", "start_time", "dateTime", "time"):
            val = obj.get(key)
            if isinstance(val, str):
                return val
            val = interval.get(key)
            if isinstance(val, str):
                return val
        for key in ("samples", "values", "measurements", "data"):
            seq = obj.get(key)
            if isinstance(seq, list) and seq:
                for item in reversed(seq):
                    val = pick_time(item)
                    if val:
                        return val
        return None

    bpm = pick_number(payload)
    time_str = pick_time(payload) or pick_time(point)
    if bpm is None:
        return None
    return int(round(bpm)), _parse_time_local(time_str)


def get_current_heart_rate():
    """آخر قراءة نبض لحظية متاحة. يرجع (bpm, local_datetime) أو None."""
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
            "",  # fallback: بعض الحسابات لا تقبل filter لهذا النوع
        ]
        for flt in filters:
            try:
                points = _list_points("heart-rate", flt, max_pages=3)
                if points:
                    all_points = points
                    break
            except GoogleHealthError as e:
                last_err = e
        if all_points:
            break

    if not all_points:
        if last_err:
            raise last_err
        return None

    samples = []
    for point in all_points:
        sample = _extract_heart_sample(point)
        if sample:
            samples.append(sample)
    if not samples:
        return None

    # اختر أحدث قراءة زمنياً، وإن غاب الوقت نأخذ آخر قراءة صالحة.
    timed = [s for s in samples if s[1] is not None]
    if timed:
        return max(timed, key=lambda x: x[1])
    return samples[-1]


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
        start_dt = _parse_time_local(interval.get("startTime"))
        end_dt = _parse_time_local(interval.get("endTime"))
        stype = st.get("type") or st.get("stage") or st.get("stageType")
        minutes = None
        if start_dt and end_dt:
            minutes = int((end_dt - start_dt).total_seconds() // 60)
        timeline.append({"type": stype, "start": start_dt, "end": end_dt, "minutes": minutes})
    sleep["_stages_timeline"] = timeline

    interval = sleep.get("interval", {})
    sleep["_local_start"] = _parse_time_local(interval.get("startTime"))
    sleep["_local_end"] = _parse_time_local(interval.get("endTime"))

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
