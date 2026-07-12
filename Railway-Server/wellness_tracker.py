"""FitbitAir 2.0 wellness storage.

Additive SQLite migrations only. Existing Fitbit, workout, and token tables are
never dropped or rewritten.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sqlite3
from typing import Any

import requests

DB_PATH = os.environ.get("GYM_DB_PATH", "gym_data.db")
QATAR = dt.timedelta(hours=3)
USER_AGENT = "FitbitAir/2.0 personal tracker (idahmad@outlook.com)"


def _conn():
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys=ON")
    return c


def today():
    return (dt.datetime.utcnow() + QATAR).date().isoformat()


def now():
    return (dt.datetime.utcnow() + QATAR).replace(microsecond=0).isoformat()


def init_db():
    # The module may be imported before webhook_app calls gym_tracker.init_db().
    # Ensure the legacy tables exist first, then apply additive wellness migrations.
    try:
        import gym_tracker
        gym_tracker.init_db()
    except Exception:
        pass
    with _conn() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS wellness_products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT UNIQUE,
          name TEXT NOT NULL,
          brand TEXT,
          serving_grams REAL,
          calories_100 REAL NOT NULL DEFAULT 0,
          protein_100 REAL NOT NULL DEFAULT 0,
          carbs_100 REAL NOT NULL DEFAULT 0,
          fat_100 REAL NOT NULL DEFAULT 0,
          image_url TEXT,
          source TEXT NOT NULL DEFAULT 'manual',
          favorite INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wellness_food_logs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          log_date TEXT NOT NULL,
          meal_type TEXT NOT NULL,
          product_id INTEGER,
          name TEXT NOT NULL,
          quantity_grams REAL NOT NULL,
          calories REAL NOT NULL,
          protein REAL NOT NULL,
          carbs REAL NOT NULL,
          fat REAL NOT NULL,
          source TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY(product_id) REFERENCES wellness_products(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_wellness_food_date ON wellness_food_logs(log_date,id);
        CREATE TABLE IF NOT EXISTS wellness_measurements(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          measure_date TEXT NOT NULL,
          weight REAL,
          waist REAL,
          chest REAL,
          arm REAL,
          thigh REAL,
          note TEXT,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wellness_body_analyses(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          analysis_date TEXT NOT NULL,
          baseline_date TEXT,
          current_date TEXT,
          pose TEXT,
          summary TEXT NOT NULL,
          visible_changes_json TEXT,
          areas_improved_json TEXT,
          areas_to_focus_json TEXT,
          confidence TEXT,
          photo_consistency TEXT,
          estimated_body_fat_range TEXT,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wellness_set_feedback(
          set_id INTEGER PRIMARY KEY,
          rpe INTEGER,
          pain INTEGER NOT NULL DEFAULT 0,
          note TEXT,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wellness_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          day_key TEXT,
          started_at TEXT NOT NULL,
          ended_at TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          effort INTEGER,
          note TEXT
        );
        CREATE TABLE IF NOT EXISTS wellness_alternatives(
          exercise TEXT PRIMARY KEY,
          alternatives_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wellness_reports(
          report_key TEXT PRIMARY KEY,
          report_type TEXT NOT NULL,
          report_date TEXT NOT NULL,
          summary TEXT NOT NULL,
          details TEXT,
          created_at TEXT NOT NULL
        );
        """)
        columns = {row[1] for row in c.execute("PRAGMA table_info(body_profile)").fetchall()}
        if "carb_grams" not in columns:
            c.execute("ALTER TABLE body_profile ADD COLUMN carb_grams INTEGER")
        if "fat_grams" not in columns:
            c.execute("ALTER TABLE body_profile ADD COLUMN fat_grams INTEGER")


def f(v, default=0.0):
    try: return float(v)
    except (TypeError, ValueError): return default


def clean(v, n=300):
    return " ".join(str(v or "").strip().split())[:n]


def valid_date(v):
    try: return dt.date.fromisoformat(str(v)).isoformat()
    except Exception: return today()


def product_payload(row):
    r = dict(row)
    return {
        "id": int(r["id"]), "barcode": r.get("barcode"), "name": r.get("name") or "منتج",
        "brand": r.get("brand") or "", "serving_grams": r.get("serving_grams"),
        "calories_per_100": round(f(r.get("calories_100")),1),
        "protein_per_100": round(f(r.get("protein_100")),1),
        "carbs_per_100": round(f(r.get("carbs_100")),1),
        "fat_per_100": round(f(r.get("fat_100")),1),
        "image_url": r.get("image_url"), "source": r.get("source") or "manual",
        "favorite": bool(r.get("favorite")),
    }


def upsert_product(x):
    name = clean(x.get("name"))
    if len(name) < 2: raise ValueError("اسم المنتج مطلوب")
    barcode = re.sub(r"\D", "", str(x.get("barcode") or "")) or None
    vals = (
        barcode, name, clean(x.get("brand"),100), f(x.get("serving_grams")) or None,
        max(0,f(x.get("calories_per_100"))), max(0,f(x.get("protein_per_100"))),
        max(0,f(x.get("carbs_per_100"))), max(0,f(x.get("fat_per_100"))),
        x.get("image_url"), clean(x.get("source") or "manual",40), 1 if x.get("favorite") else 0,
        now(), now(),
    )
    with _conn() as c:
        if barcode:
            c.execute("""INSERT INTO wellness_products(
              barcode,name,brand,serving_grams,calories_100,protein_100,carbs_100,fat_100,image_url,source,favorite,created_at,updated_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(barcode) DO UPDATE SET
              name=excluded.name,brand=excluded.brand,serving_grams=excluded.serving_grams,
              calories_100=excluded.calories_100,protein_100=excluded.protein_100,
              carbs_100=excluded.carbs_100,fat_100=excluded.fat_100,
              image_url=COALESCE(excluded.image_url,wellness_products.image_url),source=excluded.source,updated_at=excluded.updated_at""", vals)
            row = c.execute("SELECT * FROM wellness_products WHERE barcode=?",(barcode,)).fetchone()
        else:
            existing = c.execute(
                "SELECT id FROM wellness_products WHERE barcode IS NULL AND name=? AND COALESCE(brand,'')=? ORDER BY id DESC LIMIT 1",
                (name, clean(x.get("brand"), 100)),
            ).fetchone()
            if existing:
                c.execute("""UPDATE wellness_products SET
                  serving_grams=?,calories_100=?,protein_100=?,carbs_100=?,fat_100=?,
                  image_url=COALESCE(?,image_url),source=?,updated_at=? WHERE id=?""",(
                    f(x.get("serving_grams")) or None,
                    max(0,f(x.get("calories_per_100"))), max(0,f(x.get("protein_per_100"))),
                    max(0,f(x.get("carbs_per_100"))), max(0,f(x.get("fat_per_100"))),
                    x.get("image_url"), clean(x.get("source") or "manual",40), now(), int(existing["id"]),
                ))
                row = c.execute("SELECT * FROM wellness_products WHERE id=?",(int(existing["id"]),)).fetchone()
            else:
                cur = c.execute("""INSERT INTO wellness_products(
                  barcode,name,brand,serving_grams,calories_100,protein_100,carbs_100,fat_100,image_url,source,favorite,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""", vals)
                row = c.execute("SELECT * FROM wellness_products WHERE id=?",(cur.lastrowid,)).fetchone()
    return product_payload(row)


def products(q="", favorites=False, limit=80):
    where=[]; params=[]
    if q.strip():
        like=f"%{q.strip()}%"; where.append("(name LIKE ? OR brand LIKE ? OR barcode LIKE ?)"); params += [like,like,like]
    if favorites: where.append("favorite=1")
    clause=(" WHERE "+" AND ".join(where)) if where else ""
    params.append(max(1,min(int(limit),100)))
    with _conn() as c:
        rows=c.execute(f"SELECT * FROM wellness_products{clause} ORDER BY favorite DESC,updated_at DESC LIMIT ?",params).fetchall()
    return [product_payload(r) for r in rows]


def favorite(product_id, value):
    with _conn() as c:
        c.execute("UPDATE wellness_products SET favorite=?,updated_at=? WHERE id=?",(1 if value else 0,now(),int(product_id)))
        row=c.execute("SELECT * FROM wellness_products WHERE id=?",(int(product_id),)).fetchone()
    if not row: raise ValueError("المنتج غير موجود")
    return product_payload(row)


def _nutri(n, key):
    return max(0,f(n.get(f"{key}_100g", n.get(key,0))))


def lookup_barcode(code):
    code=re.sub(r"\D","",str(code or ""))
    if not 8 <= len(code) <= 14: raise ValueError("الباركود غير صالح")
    with _conn() as c:
        row=c.execute("SELECT * FROM wellness_products WHERE barcode=?",(code,)).fetchone()
    if row: return {"found":True,"product":product_payload(row),"cached":True}
    fields="code,product_name,product_name_ar,brands,serving_size,serving_quantity,nutriments,image_front_small_url,image_front_url"
    try:
        r=requests.get(f"https://world.openfoodfacts.org/api/v2/product/{code}.json",params={"fields":fields},headers={"User-Agent":USER_AGENT},timeout=14)
    except requests.RequestException as e: raise RuntimeError("تعذر الاتصال بقاعدة المنتجات") from e
    if r.status_code != 200: raise RuntimeError("تعذر البحث عن المنتج")
    raw=r.json(); p=raw.get("product") or {}
    if raw.get("status") != 1 or not p: return {"found":False,"barcode":code,"cached":False}
    serving=f(p.get("serving_quantity")) or None
    if not serving:
        m=re.search(r"([0-9]+(?:[.,][0-9]+)?)\s*g",str(p.get("serving_size") or ""),re.I)
        serving=f(m.group(1).replace(",",".")) if m else None
    n=p.get("nutriments") or {}
    item=upsert_product({
        "barcode":code,"name":p.get("product_name_ar") or p.get("product_name") or "منتج بدون اسم",
        "brand":p.get("brands"),"serving_grams":serving,
        "calories_per_100":_nutri(n,"energy-kcal"),"protein_per_100":_nutri(n,"proteins"),
        "carbs_per_100":_nutri(n,"carbohydrates"),"fat_per_100":_nutri(n,"fat"),
        "image_url":p.get("image_front_small_url") or p.get("image_front_url"),"source":"open_food_facts",
    })
    return {"found":True,"product":item,"cached":False}


def nutrition_day(date=None):
    date=valid_date(date or today())
    with _conn() as c:
        rows=c.execute("SELECT * FROM wellness_food_logs WHERE log_date=? ORDER BY id",(date,)).fetchall()
        profile=c.execute("SELECT target_weight,daily_calories,protein_grams,carb_grams,fat_grams FROM body_profile WHERE id=1").fetchone()
    entries=[dict(r) for r in rows]
    totals={k:round(sum(f(x.get(k)) for x in entries),1) for k in ("calories","protein","carbs","fat")}
    targets={"calories":int(profile["daily_calories"]) if profile and profile["daily_calories"] is not None else None,
             "protein":int(profile["protein_grams"]) if profile and profile["protein_grams"] is not None else None,
             "carbs":int(profile["carb_grams"]) if profile and profile["carb_grams"] is not None else None,
             "fat":int(profile["fat_grams"]) if profile and profile["fat_grams"] is not None else None}
    remaining={key:(round(targets[key]-totals[key],1) if targets[key] is not None else None)
               for key in ("calories","protein","carbs","fat")}
    return {"date":date,"totals":totals,"targets":targets,"remaining":remaining,"entries":entries}


def nutrition_range(days=7):
    days=max(1,min(int(days),90)); end=dt.date.fromisoformat(today())
    series=[nutrition_day((end-dt.timedelta(days=i)).isoformat()) for i in reversed(range(days))]
    logged=[x for x in series if x["entries"]]
    avg={k:round(sum(x["totals"][k] for x in logged)/len(logged),1) if logged else 0 for k in ("calories","protein","carbs","fat")}
    return {"days":series,"averages":avg,"logged_days":len(logged)}


def log_food(x):
    # Built-in and user-created meal slots are both supported. SQLite stores
    # the label/key as UTF-8 text, so a user can add unlimited meal names.
    meal=clean(x.get("meal_type") or "snack", 80).strip()
    if not meal:
        meal="snack"
    qty=f(x.get("quantity_grams"),100)
    if not 0 < qty <= 5000: raise ValueError("الكمية غير صالحة")
    pid=x.get("product_id")
    if pid is not None:
        with _conn() as c: row=c.execute("SELECT * FROM wellness_products WHERE id=?",(int(pid),)).fetchone()
        if not row: raise ValueError("المنتج غير موجود")
        p=product_payload(row)
    else:
        p=upsert_product(x.get("product") or x); pid=p["id"]
    factor=qty/100
    vals={"calories":round(p["calories_per_100"]*factor,1),"protein":round(p["protein_per_100"]*factor,1),"carbs":round(p["carbs_per_100"]*factor,1),"fat":round(p["fat_per_100"]*factor,1)}
    date=valid_date(x.get("date") or today())
    with _conn() as c:
        cur=c.execute("""INSERT INTO wellness_food_logs(log_date,meal_type,product_id,name,quantity_grams,calories,protein,carbs,fat,source,created_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)""",(date,meal,int(pid),p["name"],qty,vals["calories"],vals["protein"],vals["carbs"],vals["fat"],p["source"],now()))
    return {"saved_id":cur.lastrowid,**nutrition_day(date)}


def delete_food(log_id):
    """Delete one food log and return its date so the API can refresh totals."""
    with _conn() as c:
        row = c.execute(
            "SELECT log_date FROM wellness_food_logs WHERE id=?",
            (int(log_id),),
        ).fetchone()
        if not row:
            return None
        c.execute("DELETE FROM wellness_food_logs WHERE id=?", (int(log_id),))
        return row["log_date"]


def save_measurement(x):
    date=valid_date(x.get("date") or today())
    vals={k:(f(x.get(k),-1) if x.get(k) not in (None,"") else None) for k in ("weight","waist","chest","arm","thigh")}
    if any(v is not None and v <= 0 for v in vals.values()): raise ValueError("تأكد من القياسات")
    with _conn() as c:
        cur=c.execute("INSERT INTO wellness_measurements(measure_date,weight,waist,chest,arm,thigh,note,created_at) VALUES(?,?,?,?,?,?,?,?)",
                      (date,vals["weight"],vals["waist"],vals["chest"],vals["arm"],vals["thigh"],clean(x.get("note"),500),now()))
    if vals["weight"] is not None:
        try:
            import gym_tracker; gym_tracker.add_body_weight(vals["weight"],logged_at=f"{date}T08:00:00")
        except Exception: pass
    return {"saved_id":cur.lastrowid,**body_progress()}


def body_progress(limit=60):
    with _conn() as c:
        rows=c.execute("SELECT * FROM wellness_measurements ORDER BY measure_date DESC,id DESC LIMIT ?",(max(1,min(int(limit),180)),)).fetchall()
        analyses=c.execute("SELECT * FROM wellness_body_analyses ORDER BY id DESC LIMIT 20").fetchall()
    entries=[dict(r) for r in rows]; latest=entries[0] if entries else None; prev=entries[1] if len(entries)>1 else None
    changes={k:(round(f(latest[k])-f(prev[k]),1) if latest and prev and latest.get(k) is not None and prev.get(k) is not None else None) for k in ("weight","waist","chest","arm","thigh")}
    out=[]
    for row in analyses:
        x=dict(row)
        for src,dst in (("visible_changes_json","visible_changes"),("areas_improved_json","areas_improved"),("areas_to_focus_json","areas_to_focus")):
            try: x[dst]=json.loads(x.pop(src) or "[]")
            except Exception: x[dst]=[]
        out.append(x)
    return {"entries":entries,"latest":latest,"changes":changes,"analyses":out}


def save_body_analysis(x):
    summary=clean(x.get("summary"),5000)
    if not summary: raise ValueError("التحليل فارغ")
    with _conn() as c:
        cur=c.execute("""INSERT INTO wellness_body_analyses(analysis_date,baseline_date,current_date,pose,summary,visible_changes_json,areas_improved_json,areas_to_focus_json,confidence,photo_consistency,estimated_body_fat_range,created_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",(
          today(),x.get("baseline_date"),x.get("current_date"),clean(x.get("pose"),20),summary,
          json.dumps(x.get("visible_changes") or [],ensure_ascii=False),json.dumps(x.get("areas_improved") or [],ensure_ascii=False),
          json.dumps(x.get("areas_to_focus") or [],ensure_ascii=False),clean(x.get("confidence"),50),clean(x.get("photo_consistency"),500),clean(x.get("estimated_body_fat_range"),100),now()))
    return {"id":cur.lastrowid,"summary":summary}


def save_set_feedback(set_id,rpe=None,pain=False,note=""):
    rv=None if rpe in (None,"") else max(1,min(10,int(rpe)))
    with _conn() as c:
        c.execute("INSERT INTO wellness_set_feedback(set_id,rpe,pain,note,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(set_id) DO UPDATE SET rpe=excluded.rpe,pain=excluded.pain,note=excluded.note,updated_at=excluded.updated_at",
                  (int(set_id),rv,1 if pain else 0,clean(note,500),now()))


def decorate_sets(items):
    ids=[int(x["id"]) for x in items if x.get("id") is not None]; fb={}
    if ids:
        q=",".join("?" for _ in ids)
        with _conn() as c: rows=c.execute(f"SELECT * FROM wellness_set_feedback WHERE set_id IN ({q})",ids).fetchall()
        fb={int(r["set_id"]):dict(r) for r in rows}
    out=[]
    for item in items:
        x=dict(item); y=fb.get(int(x["id"])) if x.get("id") is not None else None
        x.update({"rpe":y.get("rpe") if y else None,"pain":bool(y.get("pain")) if y else False,"note":y.get("note") if y else ""}); out.append(x)
    return out


def log_session(x):
    sec=max(1,min(int(x.get("duration_seconds") or 0),43200)); ended=now(); started=(dt.datetime.fromisoformat(ended)-dt.timedelta(seconds=sec)).isoformat()
    effort=None if x.get("effort") in (None,"") else max(1,min(10,int(x.get("effort"))))
    with _conn() as c:
        cur=c.execute("INSERT INTO wellness_sessions(day_key,started_at,ended_at,duration_seconds,effort,note) VALUES(?,?,?,?,?,?)",
                      (clean(x.get("day_key"),80),started,ended,sec,effort,clean(x.get("note"),500)))
    return {"id":cur.lastrowid,"duration_seconds":sec,"started_at":started,"ended_at":ended}


def cached_alternatives(exercise):
    with _conn() as c: row=c.execute("SELECT alternatives_json FROM wellness_alternatives WHERE exercise=?",(clean(exercise),)).fetchone()
    if not row: return None
    try: return list(json.loads(row[0]))[:8]
    except Exception: return None


def save_alternatives(exercise,items):
    result=[]
    for item in items:
        v=clean(item,160)
        if v and v not in result: result.append(v)
    result=result[:8]
    with _conn() as c:
        c.execute("INSERT INTO wellness_alternatives(exercise,alternatives_json,updated_at) VALUES(?,?,?) ON CONFLICT(exercise) DO UPDATE SET alternatives_json=excluded.alternatives_json,updated_at=excluded.updated_at",
                  (clean(exercise),json.dumps(result,ensure_ascii=False),now()))
    return result


def save_report(kind,date,summary,details):
    key=f"{kind}:{date}"
    with _conn() as c:
        c.execute("INSERT INTO wellness_reports(report_key,report_type,report_date,summary,details,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(report_key) DO UPDATE SET summary=excluded.summary,details=excluded.details,created_at=excluded.created_at",
                  (key,kind,date,summary,details,now()))
    return {"report_type":kind,"date":date,"summary":summary,"details":details,"created_at":now()}


def get_report(kind,date):
    with _conn() as c: row=c.execute("SELECT * FROM wellness_reports WHERE report_key=?",(f"{kind}:{date}",)).fetchone()
    return dict(row) if row else None


def coach_context():
    n=nutrition_range(7); t=nutrition_day(); b=body_progress(20)
    lines=["التغذية والجسم:",f"- اليوم: {t['totals']['calories']} سعرة، بروتين {t['totals']['protein']}غ، كارب {t['totals']['carbs']}غ، دهون {t['totals']['fat']}غ."]
    if t['remaining']['calories'] is not None: lines.append(f"- المتبقي: {t['remaining']['calories']} سعرة و{t['remaining']['protein']}غ بروتين.")
    lines.append(f"- متوسط 7 أيام مسجلة: {n['averages']['calories']} سعرة و{n['averages']['protein']}غ بروتين؛ أيام التسجيل {n['logged_days']}.")
    if b['latest']:
        vals=[f"{k}={b['latest'][k]}" for k in ("weight","waist","chest","arm","thigh") if b['latest'].get(k) is not None]
        lines.append("- آخر قياسات: "+"، ".join(vals))
    if b['analyses']: lines.append("- آخر تحليل صور: "+clean(b['analyses'][0].get('summary'),500))

    try:
        with _conn() as c:
            feedback = c.execute("""SELECT f.rpe,f.pain,f.note,s.exercise,s.logged_at
              FROM wellness_set_feedback f JOIN sets s ON s.id=f.set_id
              ORDER BY s.logged_at DESC,s.id DESC LIMIT 40""").fetchall()
            sessions = c.execute("SELECT duration_seconds,effort,note,ended_at FROM wellness_sessions ORDER BY id DESC LIMIT 7").fetchall()
        rpes=[int(row['rpe']) for row in feedback if row['rpe'] is not None]
        pain_rows=[row for row in feedback if int(row['pain'] or 0)>0]
        if rpes or pain_rows:
            lines.append("إجهاد التمرين:")
            if rpes: lines.append(f"- متوسط RPE لآخر الجولات المسجلة: {round(sum(rpes)/len(rpes),1)}/10.")
            lines.append(f"- جولات عليها علامة ألم: {len(pain_rows)} من آخر {len(feedback)} جولة ذات ملاحظات.")
            notes=[clean(row['note'],120) for row in feedback if clean(row['note'],120)]
            if notes: lines.append("- آخر ملاحظات: "+" | ".join(notes[:4]))
        if sessions:
            avg_minutes=round(sum(int(row['duration_seconds']) for row in sessions)/len(sessions)/60)
            lines.append(f"- متوسط مدة آخر {len(sessions)} جلسات مسجلة: {avg_minutes} دقيقة.")
    except sqlite3.Error:
        pass
    return "\n".join(lines)


init_db()


# Stable aliases used by the iOS routes.
def qatar_today():
    return today()


def list_products(query="", favorites=False, limit=80):
    return products(query, favorites, limit)


def toggle_favorite(product_id, value):
    return favorite(product_id, value)


def save_profile_macros(target_weight=None, daily_calories=None, protein_grams=None, carb_grams=None, fat_grams=None):
    init_db()
    with _conn() as c:
        row = c.execute("SELECT * FROM body_profile WHERE id=1").fetchone()
        old = dict(row) if row else {}
        c.execute("""INSERT OR REPLACE INTO body_profile
          (id,target_weight,daily_calories,protein_grams,carb_grams,fat_grams,updated_at)
          VALUES(1,?,?,?,?,?,?)""",(
            target_weight if target_weight is not None else old.get("target_weight"),
            daily_calories if daily_calories is not None else old.get("daily_calories"),
            protein_grams if protein_grams is not None else old.get("protein_grams"),
            carb_grams if carb_grams is not None else old.get("carb_grams"),
            fat_grams if fat_grams is not None else old.get("fat_grams"),
            now(),
        ))


def extended_body_summary():
    init_db()
    import gym_tracker
    base = gym_tracker.get_body_summary()
    with _conn() as c:
        profile = c.execute("SELECT * FROM body_profile WHERE id=1").fetchone()
    p = dict(profile) if profile else {}
    progress = body_progress(60)
    latest = progress.get("latest") or {}
    base["profile"] = {
        "target_weight": p.get("target_weight"),
        "daily_calories": p.get("daily_calories"),
        "protein_grams": p.get("protein_grams"),
        "carb_grams": p.get("carb_grams"),
        "fat_grams": p.get("fat_grams"),
    }
    base["latest_waist"] = latest.get("waist")
    base["measurements"] = []
    base["analyses"] = []
    return base
