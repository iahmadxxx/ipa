from webhook_app import _device_contract, _heart_contract

DEVICE_KEYS = {
    "ok", "status", "connected", "needs_reauth", "device",
    "battery_level", "battery_status", "last_sync_time",
    "message", "reauth_url",
}
HEART_KEYS = {
    "ok", "status", "bpm", "measured_at", "age_seconds",
    "stale", "needs_reauth", "message",
}

def run():
    device_cases = [
        _device_contract("ok", device="Fitbit Air", battery_level=67, battery_status="charging", last_sync_time="2026-07-09T04:20:00Z"),
        _device_contract("ok", device="Fitbit Air", battery_level=None, battery_status="LOW"),
        _device_contract("reauth", message="reauth", reauth_url="https://example.com"),
        _device_contract("unavailable", message="temp"),
    ]
    for item in device_cases:
        assert set(item) == DEVICE_KEYS
        assert item["status"] in {"ok", "reauth", "unavailable"}
        assert isinstance(item["needs_reauth"], bool)
        assert item["battery_level"] is None or 0 <= item["battery_level"] <= 100

    heart_cases = [
        _heart_contract("ok", bpm=98, measured_at="2026-07-09T09:00:00Z", age_seconds=12),
        _heart_contract("ok", bpm=102, measured_at="2026-07-09T08:00:00Z", age_seconds=600),
        _heart_contract("no_data", message="none"),
        _heart_contract("reauth", message="reauth"),
        _heart_contract("unavailable", message="temp"),
    ]
    for item in heart_cases:
        assert set(item) == HEART_KEYS
        assert item["status"] in {"ok", "no_data", "reauth", "unavailable"}
        assert isinstance(item["stale"], bool)
        assert isinstance(item["needs_reauth"], bool)

    assert heart_cases[0]["stale"] is False
    assert heart_cases[1]["stale"] is True
    print("Contract tests: OK")

if __name__ == "__main__":
    run()
