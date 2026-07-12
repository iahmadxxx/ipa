"""Regression test for Google Health exercise session filter syntax."""
import google_health_client as gh


def run():
    value = gh._exercise_time_filter(
        "2026-07-01T21:00:00Z",
        "2026-07-12T21:00:00Z",
    )
    assert "exercise.interval.civil_start_time" in value, value
    assert "exercise.interval.start_time" not in value, value
    assert '>= "2026-06-30"' in value, value
    assert '< "2026-07-13"' in value, value
    print("Google activity filter regression test: OK")


if __name__ == "__main__":
    run()
