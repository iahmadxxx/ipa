"""Offline regression test for FitbitAir 2.0 wellness API contracts.

No real Google, Telegram, Gemini, or Open Food Facts request is made.
"""
import os
import tempfile

_fd, _db = tempfile.mkstemp(prefix="fitbitair-wellness-", suffix=".db")
os.close(_fd)
os.unlink(_db)
os.environ["GYM_DB_PATH"] = _db
os.environ["IOS_API_KEY"] = "test-key"
os.environ.setdefault("TELEGRAM_BOT_TOKEN", "dummy")
os.environ.setdefault("TELEGRAM_CHAT_ID", "123")
os.environ.setdefault("GEMINI_API_KEY", "dummy")

import webhook_app as w  # noqa: E402


def run():
    headers = {"Authorization": "Bearer test-key"}
    client = w.app.test_client()

    w.wellness_tracker.lookup_barcode = lambda code: {
        "found": True,
        "cached": False,
        "product": {
            "id": 1,
            "barcode": code,
            "name": "Test Bar",
            "brand": "Brand",
            "serving_grams": 50,
            "calories_per_100": 400.0,
            "protein_per_100": 20.0,
            "carbs_per_100": 50.0,
            "fat_per_100": 12.0,
            "image_url": None,
            "source": "test",
            "favorite": False,
        },
    }

    def fake_images(_prompt, images, **_kwargs):
        if len(images) == 2:
            return {
                "summary": "تحسن بصري بسيط",
                "visible_changes": ["الخصر أوضح"],
                "areas_improved": ["الكتف"],
                "areas_to_focus": ["الظهر"],
                "confidence": "متوسط",
                "photo_consistency": "جيدة",
                "estimated_body_fat_range": "تقديري فقط",
            }
        return {
            "name": "دجاج ورز",
            "brand": "",
            "serving_grams": 300,
            "calories_per_100": 170,
            "protein_per_100": 14,
            "carbs_per_100": 20,
            "fat_per_100": 4,
            "estimated_total_grams": 300,
            "estimated_total_calories": 510,
            "items": [],
            "confidence": "متوسط",
            "notes": "راجع الكمية",
        }

    w.analyze_images_json = fake_images
    w.generate_structured_json = lambda *_a, **_k: {
        "alternatives": ["دامبل — بديل عملي", "جهاز — تحكم أفضل"],
        "summary": "تقرير مختصر",
        "details": "1. استمر",
        "nutrition_note": "سجل أكلك",
        "training_note": "تمرن حسب الجاهزية",
    }
    w._dashboard_payload = lambda date: {
        "date": date,
        "steps": 8000,
        "calories": 2200,
        "resting_hr": 58,
        "current_hr": 72,
        "current_hr_time": "2026-07-11T10:00:00+03:00",
        "sleep_minutes": 450,
        "readiness": "78/100",
        "today_plan": "تمرين متوسط",
    }
    w.gym_tracker.get_day_summary = lambda _date: {"sets": 4}
    w.gym_tracker.build_full_coach_context = lambda **_k: "workout context"

    r = client.post(
        "/api/ios/body/profile",
        headers=headers,
        json={
            "target_weight": 67,
            "daily_calories": 2100,
            "protein_grams": 150,
            "carb_grams": 220,
            "fat_grams": 65,
        },
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["profile"]["carb_grams"] == 220

    assert client.post("/api/ios/body/weight", headers=headers, json={"weight": 69.2}).status_code == 200
    assert client.post(
        "/api/ios/body/measurement",
        headers=headers,
        json={"date": "2026-07-11", "waist": 82.4, "note": "morning"},
    ).status_code == 200
    assert client.get("/api/ios/body", headers=headers).get_json()["latest_waist"] == 82.4

    food = {
        "meal_type": "lunch",
        "quantity_grams": 100,
        "product": {
            "name": "Chicken",
            "brand": "",
            "calories_per_100": 165,
            "protein_per_100": 31,
            "carbs_per_100": 0,
            "fat_per_100": 3.6,
            "serving_grams": 100,
            "source": "manual",
        },
    }
    r = client.post("/api/ios/nutrition/log", headers=headers, json=food)
    assert r.status_code == 200, r.data
    payload = r.get_json()
    assert payload["totals"]["protein"] == 31.0

    # User-created meal slots are not restricted to the four legacy meals.
    custom_food = {**food, "meal_type": "بعد التمرين", "quantity_grams": 150}
    custom = client.post("/api/ios/nutrition/log", headers=headers, json=custom_food)
    assert custom.status_code == 200, custom.data
    custom_payload = custom.get_json()
    assert any(x["meal_type"] == "بعد التمرين" for x in custom_payload["entries"])
    assert custom_payload["totals"]["protein"] == 77.5

    assert client.post(
        "/api/ios/nutrition/log/delete",
        headers=headers,
        json={"id": payload["saved_id"]},
    ).status_code == 200
    assert client.post(
        "/api/ios/nutrition/log/delete",
        headers=headers,
        json={"id": custom_payload["saved_id"]},
    ).status_code == 200

    assert client.get(
        "/api/ios/nutrition/product/barcode?code=12345678",
        headers=headers,
    ).get_json()["found"] is True

    image = "aGVsbG8="
    assert client.post(
        "/api/ios/nutrition/analyze-image",
        headers=headers,
        json={"image_base64": image, "mode": "meal"},
    ).get_json()["analysis"]["estimated_total_calories"] == 510.0

    assert client.post(
        "/api/ios/body/analyze",
        headers=headers,
        json={
            "baseline_image_base64": image,
            "current_image_base64": image,
            "pose": "front",
            "baseline_date": "2026-06-01",
            "current_date": "2026-07-01",
        },
    ).get_json()["analysis"]["summary"] == "تحسن بصري بسيط"

    assert client.post(
        "/api/ios/workout/session",
        headers=headers,
        json={"day_key": "d1", "duration_seconds": 3600},
    ).get_json()["session"]["duration_seconds"] == 3600

    assert len(client.get(
        "/api/ios/workout/alternatives?exercise=Bench%20Press",
        headers=headers,
    ).get_json()["alternatives"]) == 2

    assert client.get("/api/ios/reports/daily?force=1", headers=headers).status_code == 200
    assert client.get("/api/ios/reports/weekly?force=1", headers=headers).status_code == 200
    assert client.get("/api/ios/nutrition/day").status_code == 401
    print("Wellness API contract tests: OK")


if __name__ == "__main__":
    try:
        run()
    finally:
        try:
            os.remove(_db)
        except FileNotFoundError:
            pass
