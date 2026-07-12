import google_health_client as gh
from datetime import date

def run():
    # Deep nested timestamp extraction must work.
    point = {
        "heartRate": {
            "samples": [
                {
                    "beatsPerMinute": 130,
                    "metadata": {
                        "timing": {
                            "interval": {
                                "endTime": "2026-07-10T09:05:00Z"
                            }
                        }
                    }
                }
            ]
        }
    }
    bpm, when = gh._extract_heart_sample(point)
    assert bpm == 130
    assert when is not None

    # Timestamp millis support.
    point2 = {
        "heartRate": {
            "value": 88,
            "timestampMillis": 1783674300000
        }
    }
    bpm2, when2 = gh._extract_heart_sample(point2)
    assert bpm2 == 88
    assert when2 is not None

    # Google Health may place the timestamp on the outer data point while the
    # one BPM value is nested. This is a valid, unambiguous sample.
    point3 = {
        "interval": {"endTime": "2026-07-12T18:30:00Z"},
        "heartRate": {"samples": [{"beatsPerMinute": 74}]},
    }
    bpm3, when3 = gh._extract_heart_sample(point3)
    assert bpm3 == 74
    assert when3 is not None
    # 18:30Z must remain the same instant. The previous implementation added
    # Qatar's +3 hours and caused live readings to be rejected as future data.
    assert when3.hour == 18 and when3.minute == 30
    assert when3.utcoffset().total_seconds() == 0

    print("Heart/RHR regression tests: OK")

if __name__ == "__main__":
    run()
