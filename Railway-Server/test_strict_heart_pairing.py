import google_health_client as gh

def run():
    # Valid: BPM and timestamp inside same sample.
    valid = {
        "heartRate": {
            "samples": [
                {"beatsPerMinute": 88, "interval": {"endTime": "2026-07-10T10:00:00Z"}},
                {"beatsPerMinute": 92, "interval": {"endTime": "2026-07-10T10:05:00Z"}},
            ]
        }
    }
    bpm, when = gh._extract_heart_sample(valid)
    assert bpm == 92
    assert when is not None

    # Critical regression: BPM in one sibling and time in another sibling.
    # Must NOT create a fake pair.
    mismatched = {
        "heartRate": {
            "samples": [
                {"beatsPerMinute": 105},
                {"interval": {"endTime": "2026-07-10T07:00:59Z"}},
            ]
        }
    }
    assert gh._extract_heart_sample(mismatched) is None

    # Another mismatch: changing BPM list + one old parent timestamp.
    # Because child sample list exists, parent timestamp must not be borrowed.
    parent_time_only = {
        "interval": {"endTime": "2026-07-10T07:00:59Z"},
        "heartRate": {
            "samples": [
                {"beatsPerMinute": 101},
                {"beatsPerMinute": 105},
            ]
        }
    }
    assert gh._extract_heart_sample(parent_time_only) is None

    # Safe single-value payload: one direct BPM + own interval.
    single = {
        "heartRate": {
            "beatsPerMinute": 77,
            "interval": {"endTime": "2026-07-10T11:00:00Z"},
        }
    }
    bpm2, when2 = gh._extract_heart_sample(single)
    assert bpm2 == 77
    assert when2 is not None

    print("Strict heart pairing regression tests: OK")

if __name__ == "__main__":
    run()
