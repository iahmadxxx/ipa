import os
import tempfile
import importlib

# Use isolated temporary DB before importing gym_tracker.
tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
os.environ["GYM_DB_PATH"] = tmp.name

import gym_tracker

def run():
    gym_tracker.DB_PATH = tmp.name
    gym_tracker.init_db()

    plan = gym_tracker.get_workout_plan()
    first_day = next(iter(plan))
    old_name = plan[first_day]["exercises"][0]

    # 1) Existing active exercise appears as current.
    ctx = gym_tracker.build_full_coach_context("وش برنامجي؟")
    assert old_name in ctx
    assert "البرنامج الحالي الفعلي الآن" in ctx

    # 2) Add a new exercise; it must appear immediately.
    new_name = "AI Context Test Exercise"
    gym_tracker.add_exercise(first_day, new_name)
    ctx = gym_tracker.build_full_coach_context("وش برنامجي؟")
    assert new_name in ctx

    # 3) Record it; its real set must appear immediately.
    gym_tracker.record_set_direct(first_day, new_name, 12, 42.5)
    ctx = gym_tracker.build_full_coach_context(new_name)
    assert "42.5كجم × 12" in ctx

    # 4) Delete it from plan; it must disappear from current active plan
    #    but remain explicitly historical because its set history is preserved.
    gym_tracker.delete_exercise(first_day, new_name)
    ctx = gym_tracker.build_full_coach_context("وش برنامجي؟")
    current_section = ctx.split("تمارين تاريخية لم تعد في البرنامج الحالي:")[0]
    assert new_name not in current_section
    assert new_name in ctx
    assert "تاريخية" in ctx or "محذوف" in ctx

    # 5) Rename active exercise; history and current plan should follow new name.
    renamed = old_name + " Renamed"
    gym_tracker.record_set_direct(first_day, old_name, 10, 30)
    gym_tracker.rename_exercise(first_day, old_name, renamed)
    ctx = gym_tracker.build_full_coach_context(renamed)
    assert renamed in ctx
    assert "30كجم × 10" in ctx

    print("Coach context regression tests: OK")

if __name__ == "__main__":
    run()
