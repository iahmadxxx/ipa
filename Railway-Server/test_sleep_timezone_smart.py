from google_health_client import _parse_sleep_time_smart

def hm(value):
    return value.hour, value.minute, int(value.utcoffset().total_seconds() // 3600)

def run():
    # Exact current screenshot:
    # Fitbit 09:58-17:28; Google source UTC 06:58-14:28.
    start = _parse_sleep_time_smart("2026-07-10T06:58:00Z")
    end = _parse_sleep_time_smart("2026-07-10T14:28:00Z")
    assert hm(start) == (9, 58, 3), start
    assert hm(end) == (17, 28, 3), end

    # Explicit Qatar offset keeps wall-clock.
    offset = _parse_sleep_time_smart("2026-07-10T09:58:00+03:00")
    assert hm(offset) == (9, 58, 3), offset

    # Zone-less source is already Qatar local.
    naive = _parse_sleep_time_smart("2026-07-10T09:58:00")
    assert hm(naive) == (9, 58, 3), naive

    # Fractional UTC.
    frac = _parse_sleep_time_smart("2026-07-10T06:58:00.123456Z")
    assert hm(frac) == (9, 58, 3), frac

    # Stage duration remains exactly 15 minutes.
    a = _parse_sleep_time_smart("2026-07-10T06:58:00Z")
    b = _parse_sleep_time_smart("2026-07-10T07:13:00Z")
    assert int((b - a).total_seconds() // 60) == 15

    print("Smart sleep timezone regression tests: OK")

if __name__ == "__main__":
    run()
