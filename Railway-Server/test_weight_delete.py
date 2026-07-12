import importlib


def test_body_weight_can_be_deleted(tmp_path, monkeypatch):
    monkeypatch.setenv("GYM_DB_PATH", str(tmp_path / "body.db"))
    import gym_tracker
    importlib.reload(gym_tracker)
    gym_tracker.init_db()

    gym_tracker.add_body_weight(70.2, logged_at="2026-07-12T08:00:00")
    summary = gym_tracker.get_body_summary()
    assert summary["latest_weight"] == 70.2
    entry_id = summary["entries"][0]["id"]

    assert gym_tracker.delete_body_weight(entry_id) is True
    summary = gym_tracker.get_body_summary()
    assert summary["entries"] == []
    assert summary["latest_weight"] is None
