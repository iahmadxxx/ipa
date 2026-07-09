"""
ai_coach.py — مدرب ذكي متعدد الأدوار مع ذاكرة محادثة (multi-turn).
"""

import os
import json
import base64
import requests

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
    key = os.environ.get("GEMINI_API_KEY")
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
        "generationConfig": {"temperature": 0.85, "maxOutputTokens": max_tokens},
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
    return f"""أنت مدرب لياقة ورياضة متكامل محترف — تتكلم بلهجة خليجية ودية ومحفزة.
تخصصك يشمل كل شيء بدون قيود: تمارين الحديد (أوزان، جولات، تكرارات، تقنية، برامج تدريبية)، كارديو، نوم، تغذية، تعافي.

بيانات المستخدم الفعلية:
{fitbit_context}{gym_section}

تعليمات التجاوب:
- جاوب مباشرة على سؤاله بدون مقدمات.
- استخدم بياناته الفعلية (الأوزان، الجولات، خطواته، نومه) في إجابتك.
- لو سأل عن تمرين: اشرح طريقته الصحيحة، عضلاته، أخطاؤه الشائعة.
- لو سأل عن برنامج أو خطة: ابنيها بناءً على ما سجّله فعلاً.
- لو كان سؤالاً متابعة (مثل "زدني" أو "وش قصدك"): أكمل من السياق السابق مباشرة.
- اكتب بالعربي بلهجة خليجية، مفصّل بقدر ما يحتاج السؤال.
- فقط لو السؤال طبي بحت (مرض، أعراض، أدوية): انصحه يراجع طبيب."""


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
