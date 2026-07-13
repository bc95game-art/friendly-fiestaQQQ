package ali.khaleghi.daewooremote

import android.content.Context
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * چون کاربر به adb/logcat یا Google Play Console دسترسی ندارد، این کلاس
 * آخرین کرش را مستقیماً روی خودِ گوشی، در یک فایل ساده داخل حافظه‌ی
 * اختصاصی اپ ذخیره می‌کند. دفعه‌ی بعد که اپ باز شود، این فایل خوانده و به
 * کاربر نشان داده می‌شود (و بعد پاک می‌شود) — تا بدون نیاز به کامپیوتر یا
 * ابزار توسعه، متن دقیق خطا را بشود کپی/اسکرین‌شات کرد و فرستاد.
 */
object CrashLogger {
    private const val FILE_NAME = "last_crash.txt"

    /** باید در اولین نقطه‌ی ممکن (Application.onCreate) صدا زده شود. */
    fun install(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val text = "Thread: ${thread.name}\n$sw"
                Log.e("DaewooRemoteCrash", text)
                File(context.filesDir, FILE_NAME).writeText(text)
            } catch (_: Throwable) {
                // اگر ذخیره‌سازی خودش شکست خورد، نباید مانع رفتار عادی کرش شود
            }
            // رفتار پیش‌فرض سیستم (دیالوگ «برنامه متوقف شد» و بستن پروسه) حفظ
            // می‌شود — این هندلر فقط برای ثبت است، نه جلوگیری از کرش.
            previous?.uncaughtException(thread, throwable)
        }
    }

    /** آخرین کرش ذخیره‌شده را برمی‌گرداند (یا null) و فایل را پاک می‌کند. */
    fun readAndClear(context: Context): String? {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.exists()) return null
        return try {
            val text = file.readText()
            file.delete()
            text
        } catch (_: Throwable) {
            null
        }
    }
}
