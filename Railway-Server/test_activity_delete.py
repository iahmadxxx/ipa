import importlib
import os


def test_activity_soft_delete_does_not_return_in_history(tmp_path, monkeypatch):
    monkeypatch.setenv("GYM_DB_PATH", str(tmp_path / "activity.db"))
    import activity_tracker
    importlib.reload(activity_tracker)

    saved = activity_tracker.save_local_session({
        "client_id": "delete-test",
        "exercise_type": "RUNNING",
        "display_name": "ركض",
        "start_time": "2026-07-12T17:00:00Z",
        "end_time": "2026-07-12T17:30:00Z",
        "duration_seconds": 1800,
        "active_seconds": 1700,
        "distance_meters": 5000,
        "has_gps": True,
        "route": [],
        "rpe": 7,
    })
    assert saved["id"]
    assert len(activity_tracker.list_sessions(days=365)) == 1

    deleted = activity_tracker.delete_session(saved["id"])
    assert deleted["id"] == saved["id"]
    assert activity_tracker.list_sessions(days=365) == []
    assert activity_tracker.summary(days=365)["sessions"] == 0
