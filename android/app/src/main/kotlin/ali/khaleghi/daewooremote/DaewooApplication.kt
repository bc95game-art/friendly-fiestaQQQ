package ali.khaleghi.daewooremote

import android.app.Application

/**
 * قبل از هر Activity اجرا می‌شود — پس زودترین نقطه‌ی ممکن برای نصب
 * گیرنده‌ی سراسری کرش است (حتی زودتر از MainActivity.onCreate).
 */
class DaewooApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLogger.install(this)
    }
}
