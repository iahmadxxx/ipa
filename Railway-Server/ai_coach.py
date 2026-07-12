"""
ai_coach.py — مدرب ذكي متعدد الأدوار مع ذاكرة محادثة (multi-turn).
"""

import os
import json
import base64
import re
import requests
import token_store

MODELS = [
    "gemini-3-flash",
    "gemini-3.1-flash-lite",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-flash-latest",
]

BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"


class AICoachError(Exception):
    pass


def _get_api_key():
    key = token_store.get_gemini_api_key()
    if not key:
        raise AICoachError("مفتاح GEMINI_API_KEY ناقص بـ env_config.py")
    return key


def _call_gemini_single(prompt, max_tokens=1000, temperature=0.7):
    """طلب بسيط بدون تاريخ محادثة — للتحليل الأسبوعي."""
    api_key = _get_api_key()
    errors = []
    for model in MODELS:
        try:
            resp = requests.post(
                f"{BASE_URL}/{model}:generateContent?key={api_key}",
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
                },
                timeout=35,
            )
            if resp.status_code == 200:
                try:
                    return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
                except (KeyError, IndexError):
                    errors.append(f"{model}: رد بصيغة غير متوقعة")
                    continue
            else:
                errors.append(f"{model}: {resp.status_code}")
        except requests.RequestException as e:
            errors.append(f"{model}: {e}")
    raise AICoachError(
        "كل النماذج فشلت:\n" + "\n".join(errors[:5])
        + "\n\n💡 افتح aistudio.google.com وشوف أسماء النماذج المتاحة."
    )


def _call_gemini_multiturn(system_instruction, history, new_question, max_tokens=1800):
    """طلب متعدد الأدوار مع تاريخ المحادثة وsystem instruction."""
    api_key = _get_api_key()

    # بناء مصفوفة المحادثة: تاريخ سابق + سؤال جديد
    contents = []
    for msg in history:
        role = msg["role"]  # "user" أو "model"
        contents.append({"role": role, "parts": [{"text": msg["content"]}]})
    contents.append({"role": "user", "parts": [{"text": new_question}]})

    payload = {
        "system_instruction": {"parts": [{"text": system_instruction}]},
        "contents": contents,
        "generationConfig": {"temperature": 0.42, "maxOutputTokens": max_tokens},
    }

    errors = []
    for model in MODELS:
        try:
            resp = requests.post(
                f"{BASE_URL}/{model}:generateContent?key={api_key}",
                json=payload,
                timeout=40,
            )
            if resp.status_code == 200:
                try:
                    return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
                except (KeyError, IndexError):
                    errors.append(f"{model}: رد بصيغة غير متوقعة")
                    continue
            else:
                errors.append(f"{model}: {resp.status_code}")
        except requests.RequestException as e:
            errors.append(f"{model}: {e}")
    raise AICoachError("كل النماذج فشلت:\n" + "\n".join(errors[:5]))


def transcribe_audio(audio_bytes, mime_type="audio/ogg"):
    api_key = _get_api_key()
    audio_b64 = base64.b64encode(audio_bytes).decode("ascii")
    prompt = (
        "حوّل هذا المقطع الصوتي إلى نص عربي مكتوب حرفيًا كما قاله المتحدث. "
        "اكتب النص فقط بدون أي شرح أو مقدمة."
    )
    errors = []
    for model in MODELS:
        try:
            resp = requests.post(
                f"{BASE_URL}/{model}:generateContent?key={api_key}",
                json={
                    "contents": [{
                        "parts": [
                            {"text": prompt},
                            {"inline_data": {"mime_type": mime_type, "data": audio_b64}},
                        ]
                    }],
                    "generationConfig": {"temperature": 0.2, "maxOutputTokens": 300},
                },
                timeout=30,
            )
            if resp.status_code == 200:
                try:
                    return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
                except (KeyError, IndexError):
                    errors.append(f"{model}: رد بصيغة غير متوقعة")
                    continue
            else:
                errors.append(f"{model}: {resp.status_code}")
        except requests.RequestException as e:
            errors.append(f"{model}: {e}")
    raise AICoachError("تعذر تحويل الصوت لنص:\n" + "\n".join(errors[:5]))


def _build_fitbit_context(week_data, today_data):
    lines = ["📊 بيانات Fitbit — آخر 7 أيام (خطوات | سعرات):"]
    for d in week_data:
        steps = d.get("steps") or "—"
        cal = d.get("calories") or "—"
        lines.append(f"  {d.get('date')}: خطوات={steps}, سعرات={cal}")
    lines.append("")
    lines.append("📊 اليوم:")
    lines.append(f"  الخطوات: {today_data.get('steps') or '—'}")
    lines.append(f"  السعرات: {today_data.get('calories') or '—'}")
    lines.append(f"  نبض الراحة: {today_data.get('heart_rate') or '—'}")
    sleep = today_data.get("sleep")
    if sleep:
        summary = sleep.get("summary", {})
        lines.append(f"  النوم (دقائق): {summary.get('minutesAsleep', '—')}")
        stages = {s.get("type"): s.get("minutes") for s in summary.get("stagesSummary", [])}
        if stages:
            lines.append(f"  مراحل النوم: {json.dumps(stages, ensure_ascii=False)}")
    else:
        lines.append("  النوم: غير متوفر")
    return "\n".join(lines)


def _build_gym_section(gym_context):
    if not gym_context:
        return ""
    return f"\n\n🏋️ سجل تمارين الحديد:\n{gym_context}"


def _build_system_instruction(fitbit_context, gym_context=None):
    gym_section = _build_gym_section(gym_context)
    return f"""أنت مساعد أحمد الذكي داخل تطبيق FitbitAir، وتتصرف كمساعد عام قوي مثل GPT، وفي نفس الوقت كمدرب شخصي يعرف بيانات أحمد عندما يكون السؤال عنه.

قدراتك:
- جاوب عن أي سؤال عام: تقنية، سفر، كتابة، ترجمة، أفكار، معرفة عامة، رياضة، تغذية وغيرها.
- عندما يسأل أحمد عن نفسه أو صحته أو تمارينه أو سجله، استخدم بياناته الفعلية أدناه.
- لا تحصر نفسك بالرياضة إذا كان السؤال عن موضوع آخر.

بيانات أحمد الفعلية:
{fitbit_context}{gym_section}

قواعد صارمة عند الكلام عن بيانات أحمد:
1. مصدر الحقيقة للبرنامج الحالي هو قسم "البرنامج الحالي الفعلي الآن" فقط.
2. لا تقل إن تمرينًا ضمن البرنامج الحالي إذا كان موسومًا "تاريخي/محذوف" أو موجودًا في قسم التمارين التاريخية.
3. إذا أضاف أحمد تمرينًا جديدًا، اعتبره نشطًا فقط إذا ظهر في البرنامج الحالي.
4. إذا سجّل تمرينًا جديدًا، اقرأ جولاته من آخر التمارين الفعلية وأدخله في التحليل فورًا.
5. إذا حذف تمرينًا، لا تعرضه ضمن قائمته الحالية ولا تقترح أنه ما زال في البرنامج. يجوز ذكره فقط كتاريخ سابق وبوضوح.
6. لا تخترع تمرينًا أو وزنًا أو عدة أو تاريخًا. إذا البيانات غير موجودة قل بوضوح إنها غير متوفرة.
7. إذا سأل "وش لعبت اليوم؟" أو "وش سجلت؟" استخدم تاريخ اليوم الفعلي من السجل واذكر كل تمرين وكل جولة ووزن وعدات.
8. إذا سأل عن تمرين محدد، استخدم تفاصيل جلساته الموجودة في السياق وقارنها زمنيًا.
9. فرّق دائمًا بين:
   - البرنامج الحالي
   - التمارين التي نفذها فعلًا
   - التمارين التاريخية المحذوفة
10. عند التحليل، استشهد بالأرقام الفعلية الموجودة في السياق بدل كلام عام.

أسلوب الرد:
- جاوب مباشرة وبوضوح.
- استخدم العربية بلهجة خليجية طبيعية ما لم يطلب لغة أخرى.
- لا تستخدم تنسيق Markdown ثقيل أو نجوم ** داخل التطبيق إلا عند الحاجة.
- في الأسئلة العامة: جاوب بشكل طبيعي مثل مساعد عام، ولا تحشر بيانات اللياقة بدون سبب.
- في الأسئلة الشخصية: كن دقيقًا ومهنيًا ومبنيًا على البيانات.
- في الأسئلة الطبية عالية الخطورة: وضح حدودك وانصح بمختص عند الحاجة."""


def analyze_week(week_data, today_data):
    context = _build_fitbit_context(week_data, today_data)
    prompt = f"""أنت مدرب لياقة شخصي محترف تتكلم بلهجة خليجية ودية ومحفزة.
هذي بيانات لياقة حقيقية من ساعة Fitbit للمستخدم:

{context}

حلل البيانات وقدم:
1. نظرة عامة قصيرة على الأسبوع (سطرين).
2. أهم نمط لاحظته — اربط بين النوم والنشاط لو ظهر رابط.
3. ثلاث نصائح عملية محددة مبنية على أرقامه هو (مو نصائح عامة).

اكتب بالعربي، مختصر ومنظم برموز تعبيرية، بدون مقدمات طويلة. لا تتجاوز 15 سطر."""
    return _call_gemini_single(prompt, max_tokens=1000, temperature=0.7)


def ask_coach(question, week_data, today_data, gym_context=None, history=None):
    """
    يجاوب على سؤال مع تاريخ المحادثة الكاملة (multi-turn).
    history = قائمة [{"role": "user"/"model", "content": "..."}]
    """
    fitbit_context = _build_fitbit_context(week_data, today_data)
    system_instruction = _build_system_instruction(fitbit_context, gym_context)
    return _call_gemini_multiturn(
        system_instruction=system_instruction,
        history=history or [],
        new_question=question,
    )


# ---------------------------------------------------------------------------
# Structured Gemini helpers for FitbitAir 2.0 image/report features
# ---------------------------------------------------------------------------

def _structured_json_from_text(text):
    value=(text or "").strip()
    value=re.sub(r"^```(?:json)?\s*", "", value, flags=re.I)
    value=re.sub(r"\s*```$", "", value)
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        starts=[x for x in (value.find("{"),value.find("[")) if x>=0]
        if not starts: raise AICoachError("رد Gemini غير منظم")
        start=min(starts); end=value.rfind("}" if value[start]=="{" else "]")
        if end<=start: raise AICoachError("تعذر قراءة رد Gemini")
        try: return json.loads(value[start:end+1])
        except json.JSONDecodeError as exc: raise AICoachError("تعذر قراءة JSON من Gemini") from exc


def generate_structured_json(prompt, max_tokens=1600, temperature=0.2):
    api_key=_get_api_key(); errors=[]
    for model in MODELS:
        try:
            r=requests.post(f"{BASE_URL}/{model}:generateContent?key={api_key}",json={
                "contents":[{"parts":[{"text":prompt}]}],
                "generationConfig":{"temperature":temperature,"maxOutputTokens":max_tokens,"responseMimeType":"application/json"},
            },timeout=45)
            if r.status_code==200:
                try: return _structured_json_from_text(r.json()["candidates"][0]["content"]["parts"][0]["text"])
                except Exception as e: errors.append(f"{model}: {e}")
            else: errors.append(f"{model}: {r.status_code}")
        except requests.RequestException as e: errors.append(f"{model}: {e}")
    raise AICoachError("تعذر إنشاء النتيجة المنظمة:\n"+"\n".join(errors[:5]))


def analyze_images_json(prompt, images, max_tokens=1900, temperature=0.15):
    if not images: raise AICoachError("لم يتم إرسال صورة")
    api_key=_get_api_key(); errors=[]; parts=[{"text":prompt}]
    for image_bytes,mime_type in images[:3]:
        parts.append({"inline_data":{"mime_type":mime_type or "image/jpeg","data":base64.b64encode(image_bytes).decode("ascii")}})
    for model in MODELS:
        try:
            r=requests.post(f"{BASE_URL}/{model}:generateContent?key={api_key}",json={
                "contents":[{"role":"user","parts":parts}],
                "generationConfig":{"temperature":temperature,"maxOutputTokens":max_tokens,"responseMimeType":"application/json"},
            },timeout=60)
            if r.status_code==200:
                try: return _structured_json_from_text(r.json()["candidates"][0]["content"]["parts"][0]["text"])
                except Exception as e: errors.append(f"{model}: {e}")
            else: errors.append(f"{model}: {r.status_code}")
        except requests.RequestException as e: errors.append(f"{model}: {e}")
    raise AICoachError("تعذر تحليل الصورة:\n"+"\n".join(errors[:5]))
