# FitbitAir iPhone — النسخة الشخصية

المجلد يحتوي على جزأين:

1. `Railway-Server` — ارفع محتوياته فوق ملفات GitHub الحالية. يحتفظ بنفس قاعدة البيانات ونفس Google Health ونفس Gemini والبوت.
2. `FitbitAir-iOS` — افتح `FitbitAir.xcodeproj` في Xcode، اختر Team الخاص بك ثم Run.

الرابط مضبوط مسبقًا على:
`https://web-production-45a08f.up.railway.app`

مفتاح التطبيق الشخصي مضمن في نسخة الخادم ونسخة التطبيق حتى يعملان مباشرة بعد رفع الملفات. إذا كان مستودع GitHub عامًا، اجعله خاصًا أو عيّن متغير Railway باسم `IOS_API_KEY` وحدث نفس القيمة في `Config.swift`.

التطبيق يستخدم نفس البيانات الحالية؛ لا ينشئ قاعدة بيانات جديدة ولا يغير Google OAuth.

## IPA عبر GitHub Actions
تمت إضافة بناء تلقائي لملف `FitbitAir-Unsigned.ipa`. راجع ملف `BUILD-IPA-WITH-GITHUB.md`.
