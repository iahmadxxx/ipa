"""Offline regression test for exercise-library plan operations."""
import os
import tempfile

_fd, _db = tempfile.mkstemp(prefix="fitbitair-exercise-library-", suffix=".db")
os.close(_fd)
os.unlink(_db)
os.environ["GYM_DB_PATH"] = _db
os.environ["IOS_API_KEY"] = "test-key"
os.environ.setdefault("TELEGRAM_BOT_TOKEN", "dummy")
os.environ.setdefault("TELEGRAM_CHAT_ID", "123")
os.environ.setdefault("GEMINI_API_KEY", "dummy")

import webhook_app as w  # noqa: E402


def run():
    client = w.app.test_client()
    headers = {"Authorization": "Bearer test-key"}

    plan = client.get("/api/ios/plan", headers=headers).get_json()["days"]
    source = plan[0]
    target = plan[1]
    original = list(source["exercises"])
    reordered = list(reversed(original))

    response = client.post(
        "/api/ios/exercise/reorder",
        headers=headers,
        json={"day": source["key"], "exercises": reordered},
    )
    assert response.status_code == 200, response.data

    plan = client.get("/api/ios/plan", headers=headers).get_json()["days"]
    assert next(x for x in plan if x["key"] == source["key"])["exercises"] == reordered

    exercise = reordered[0]
    response = client.post(
        "/api/ios/exercise/move",
        headers=headers,
        json={
            "source_day": source["key"],
            "target_day": target["key"],
            "name": exercise,
        },
    )
    assert response.status_code == 200, response.data

    plan = client.get("/api/ios/plan", headers=headers).get_json()["days"]
    source_after = next(x for x in plan if x["key"] == source["key"])
    target_after = next(x for x in plan if x["key"] == target["key"])
    assert exercise not in source_after["exercises"]
    assert exercise in target_after["exercises"]
    print("Exercise library plan tests: OK")


if __name__ == "__main__":
    try:
        run()
    finally:
        try:
            os.remove(_db)
        except FileNotFoundError:
            pass
