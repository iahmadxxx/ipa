"""Offline API contract test for FitbitAir 2.2 activity tracking."""
import os
import tempfile

_fd, _db = tempfile.mkstemp(prefix="fitbitair-activity-api-", suffix=".db")
os.close(_fd)
os.unlink(_db)
os.environ["GYM_DB_PATH"] = _db
os.environ["IOS_API_KEY"] = "test-key"
os.environ.setdefault("TELEGRAM_BOT_TOKEN", "dummy")
os.environ.setdefault("TELEGRAM_CHAT_ID", "123")
os.environ.setdefault("GEMINI_API_KEY", "dummy")

import webhook_app as w  # noqa: E402


def run():
    upload_calls = {"count": 0}
    def fake_create(payload):
        upload_calls["count"] += 1
        return {"name": "operations/test-upload"}
    w.create_exercise_session = fake_create
    w.list_exercises = lambda *_a, **_k: []

    client = w.app.test_client()
    headers = {"Authorization": "Bearer test-key"}
    payload = {
        "client_id": "ios-contract-1",
        "exercise_type": "RUNNING",
        "display_name": "ركض",
        "start_time": "2026-07-12T15:00:00.000Z",
        "end_time": "2026-07-12T15:30:00.000Z",
        "duration_seconds": 1800,
        "active_seconds": 1750,
        "distance_meters": 5000,
        "average_speed_mps": 2.85,
        "elevation_gain_meters": 12,
        "has_gps": True,
        "route": [],
        "notes": "اختبار العقد",
        "rpe": 7,
    }

    response = client.post("/api/ios/activities/session", json=payload, headers=headers)
    assert response.status_code == 200, response.get_data(as_text=True)
    body = response.get_json()
    assert body["ok"] is True
    assert body["google_status"] == "uploaded"
    assert body["session"]["exercise_type"] == "RUNNING"
    assert body["session"]["sync_status"] == "uploaded"
    assert upload_calls["count"] == 1

    # Same client_id is idempotent and must not create a duplicate Google exercise.
    duplicate = client.post("/api/ios/activities/session", json=payload, headers=headers)
    assert duplicate.status_code == 200
    assert duplicate.get_json()["message"] == "النشاط محفوظ ومتزامن مسبقًا"
    assert upload_calls["count"] == 1

    response = client.get("/api/ios/activities?days=30", headers=headers)
    assert response.status_code == 200
    body = response.get_json()
    assert body["ok"] is True
    assert len(body["sessions"]) == 1
    assert body["summary"]["sessions"] == 1
    assert body["summary"]["distance_meters"] == 5000.0

    response = client.post("/api/ios/activities/sync", json={"days": 30}, headers=headers)
    assert response.status_code == 200, response.get_data(as_text=True)
    body = response.get_json()
    assert body["ok"] is True
    assert isinstance(body["sessions"], list)
    assert set(["imported", "merged", "uploaded", "summary"]).issubset(body)


    # Missing write scope must not lose the activity; it is stored and asks for consent.
    def denied_create(_payload):
        raise w.GoogleHealthError("403 PERMISSION_DENIED insufficient scope")
    w.create_exercise_session = denied_create
    denied_payload = {**payload, "client_id": "ios-contract-needs-reauth", "start_time": "2026-07-12T16:00:00Z", "end_time": "2026-07-12T16:20:00Z"}
    denied = client.post("/api/ios/activities/session", json=denied_payload, headers=headers)
    assert denied.status_code == 200
    denied_body = denied.get_json()
    assert denied_body["ok"] is True
    assert denied_body["needs_reauth"] is True
    assert denied_body["session"]["sync_status"] == "needs_reauth"

    unauthorized = client.get("/api/ios/activities")
    assert unauthorized.status_code in (401, 403)
    print("Activity API contract tests: OK")


if __name__ == "__main__":
    try:
        run()
    finally:
        try:
            os.unlink(_db)
        except OSError:
            pass
