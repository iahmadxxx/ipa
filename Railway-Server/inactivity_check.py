"""خدمة Railway الحالية للتنبيهات — أصبحت ذكية وشخصية.

احتفظ بنفس خدمة Cron والجدول الحالي؛ لا تحتاج إنشاء خدمة جديدة.
"""
try:
    import env_config  # noqa: F401
except ImportError:
    pass

from smart_alerts import main


if __name__ == "__main__":
    main()
