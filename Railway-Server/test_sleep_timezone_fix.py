from google_health_client import _parse_sleep_time_exact

def run():
    cases = [
        ("2026-07-09T14:07:00Z", 14, 7),
        ("2026-07-09T19:08:00+00:00", 19, 8),
        ("2026-07-09T02:07:30.123456Z", 2, 7),
        ("2026-07-09T14:07:00", 14, 7),
    ]

    for raw, hour, minute in cases:
        value = _parse_sleep_time_exact(raw)
        assert value is not None, raw
        assert value.hour == hour, (raw, value)
        assert value.minute == minute, (raw, value)
        assert value.tzinfo is None, (raw, value)

    # This is the exact regression:
    # source 14:07 must stay 14:07 and must never become 17:07.
    value = _parse_sleep_time_exact("2026-07-09T14:07:00Z")
    assert value.hour != 17

    print("Sleep timezone regression tests: OK")

if __name__ == "__main__":
    run()
