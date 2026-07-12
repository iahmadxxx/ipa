import os
import tempfile
import unittest

import activity_tracker


class ActivityTrackingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        activity_tracker.DB_PATH = os.path.join(self.tmp.name, "activities.db")
        activity_tracker.init_db()

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def payload(client_id="session-1"):
        return {
            "client_id": client_id,
            "exercise_type": "RUNNING",
            "display_name": "ركض",
            "start_time": "2026-07-12T10:00:00.000Z",
            "end_time": "2026-07-12T10:30:00.000Z",
            "duration_seconds": 1800,
            "active_seconds": 1740,
            "distance_meters": 5000,
            "average_speed_mps": 2.87,
            "elevation_gain_meters": 24,
            "has_gps": True,
            "route": [{"latitude": 25.3, "longitude": 51.5, "altitude": 4, "timestamp": "2026-07-12T10:01:00Z"}],
            "notes": "اختبار",
            "rpe": 7,
        }

    def test_save_is_idempotent_and_summary_is_correct(self):
        first = activity_tracker.save_local_session(self.payload())
        second = activity_tracker.save_local_session({**self.payload(), "distance_meters": 5100})
        self.assertEqual(first["id"], second["id"])
        self.assertEqual(second["distance_meters"], 5100)
        rows = activity_tracker.list_sessions(days=365)
        self.assertEqual(len(rows), 1)
        summary = activity_tracker.summary(days=365)
        self.assertEqual(summary["sessions"], 1)
        self.assertEqual(summary["active_seconds"], 1740)
        self.assertEqual(summary["distance_meters"], 5100.0)

    def test_google_exercise_merges_matching_local_session(self):
        local = activity_tracker.save_local_session(self.payload())
        result = activity_tracker.import_google_exercises([
            {
                "dataPointName": "users/me/dataTypes/exercise/dataPoints/exercise-1",
                "exercise": {
                    "interval": {
                        "startTime": "2026-07-12T10:00:20Z",
                        "endTime": "2026-07-12T10:30:10Z",
                    },
                    "exerciseType": "RUNNING",
                    "displayName": "Run",
                    "activeDuration": "1760s",
                    "metricsSummary": {
                        "distanceMillimeters": 5050000,
                        "caloriesKcal": 410,
                        "steps": "6200",
                        "averageHeartRateBeatsPerMinute": "147",
                        "averageSpeedMillimetersPerSecond": 2820,
                        "elevationGainMillimeters": 26000,
                        "activeZoneMinutes": "25",
                    },
                    "exerciseMetadata": {"hasGps": True},
                },
            }
        ])
        self.assertEqual(result, {"imported": 0, "merged": 1})
        row = activity_tracker.get_session(local["id"])
        self.assertEqual(row["source"], "fitbitair+google_health")
        self.assertEqual(row["sync_status"], "synced")
        self.assertEqual(row["average_heart_rate"], 147)
        self.assertEqual(row["calories"], 410.0)
        self.assertEqual(len(activity_tracker.list_sessions(days=365)), 1)


    def test_related_google_type_merges_without_duplicate(self):
        local_payload = {**self.payload("bike-1"), "exercise_type": "OUTDOOR_BIKE", "display_name": "دراجة خارجية"}
        local = activity_tracker.save_local_session(local_payload)
        result = activity_tracker.import_google_exercises([{
            "dataPointName": "users/me/dataTypes/exercise/dataPoints/bike-fitbit",
            "exercise": {
                "interval": {"startTime": "2026-07-12T10:01:00Z", "endTime": "2026-07-12T10:31:00Z"},
                "exerciseType": "BIKING",
                "displayName": "Bike",
                "metricsSummary": {"distanceMillimeters": 10000000},
            },
        }])
        self.assertEqual(result["merged"], 1)
        self.assertEqual(len(activity_tracker.list_sessions(days=365)), 1)
        self.assertEqual(activity_tracker.get_session(local["id"])["sync_status"], "synced")

    def test_google_only_exercise_is_imported_once(self):
        point = {
            "name": "users/me/dataSources/source/dataPoints/exercise-unique",
            "exercise": {
                "interval": {"startTime": "2026-07-11T07:00:00Z", "endTime": "2026-07-11T08:00:00Z"},
                "exerciseType": "BIKING",
                "displayName": "Cycling",
                "metricsSummary": {"distanceMillimeters": 18000000},
            },
        }
        first = activity_tracker.import_google_exercises([point])
        second = activity_tracker.import_google_exercises([point])
        self.assertEqual(first["imported"], 1)
        self.assertEqual(second["imported"], 0)
        self.assertEqual(len(activity_tracker.list_sessions(days=365)), 1)

    def test_invalid_interval_is_rejected(self):
        with self.assertRaises(ValueError):
            activity_tracker.save_local_session({**self.payload(), "end_time": "2026-07-12T09:00:00Z"})


if __name__ == "__main__":
    unittest.main()
