package ali.khaleghi.tvdiagnostic

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * سرویس دسترسی‌پذیریِ اختیاری — تنها برای گرفتن دکمه‌هایی که خودِ اندروید
 * قبل از رسیدن به هر اپ عادی (از جمله MainActivity همین اپ) مصرف می‌کند:
 * HOME، VOLUME_UP/DOWN، MUTE و مشابه. این کلیدها هرگز به
 * Activity.dispatchKeyEvent/onKeyDown یا حتی به یک BroadcastReceiver عادی
 * نمی‌رسند — AccessibilityService تنها راهِ غیرِ ریشه‌ای (non-root) روی
 * اندروید برای دیدن این دکمه‌ها در سطح سیستم است.
 *
 * فعال‌سازی این سرویس نیاز به تأیید دستی کاربر در
 * تنظیمات ›  دسترسی‌پذیری دارد — به دلایل امنیتی، هیچ اپی
 * (حتی این اپ) نمی‌تواند آن را بدون اجازه‌ی صریح کاربر فعال کند.
 *
 * رویدادهای گرفته‌شده از طریق یک broadcast محلی (فقط داخل همین اپ،
 * با setPackage) به [MainActivity] فرستاده می‌شوند تا از همان مسیر
 * EventChannel موجود (daewoo_tv_diag/keys) به Flutter برسند — یعنی
 * سمتِ Dart هیچ تغییری نیاز ندارد.
 */
class KeyAccessibilityService : AccessibilityService() {

    companion object {
        const val ACTION_KEY = "ali.khaleghi.tvdiagnostic.ACCESSIBILITY_KEY"
        const val EXTRA_LINE = "line"
    }

    private val timeFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 0
        }
        serviceInfo = info
    }

    // فرمت پیام دقیقاً همان فرمتی است که MainActivity.sendKeyEvent تولید می‌کند:
    // time|action|keyCode|keyName|scanCode|source|deviceId|deviceName|repeat
    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val time = timeFmt.format(Date())
            val keyName = KeyEvent.keyCodeToString(event.keyCode)
            val line = "$time|DOWN|${event.keyCode}|$keyName|${event.scanCode}|A11Y|" +
                "${event.deviceId}|سرویس دسترسی‌پذیری|0"
            val intent = Intent(ACTION_KEY).apply {
                putExtra(EXTRA_LINE, line)
                setPackage(packageName)
            }
            sendBroadcast(intent)
        }
        // false: رویداد را مصرف نکن، بگذار مسیر عادی سیستم هم آن را ببیند
        // (مثلاً بروزرسانی نوار ولوم سیستمی به‌کار خودش ادامه بدهد)
        return false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}

    override fun onInterrupt() {}
}
