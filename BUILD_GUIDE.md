# راهنمای ساخت APK — کنترل هوشمند دوو

## پیش‌نیازها

| ابزار | نسخه | لینک |
|-------|------|------|
| Flutter SDK | 3.3.0 یا بالاتر | https://flutter.dev |
| Android Studio | هر نسخه | https://developer.android.com/studio |
| Android SDK | API 34 | از طریق Android Studio |
| Java/JDK | 17 یا بالاتر | همراه Android Studio |

---

## روش ساخت APK — مرحله به مرحله

### مرحله ۱ — اولین بار (فقط یک بار)
```bash
# اجرای اسکریپت آماده‌سازی
bash SETUP.sh
```
این اسکریپت خودکار:
- فایل‌های باینری Gradle را دانلود می‌کند
- تمام پکیج‌های Flutter را نصب می‌کند

### مرحله ۲ — ساخت APK
```bash
# نسخه debug برای تست اولیه (سریع‌تر):
flutter build apk --debug

# نسخه release برای استفاده نهایی:
flutter build apk --release
```

### مرحله ۳ — نصب روی گوشی
```bash
# اتصال گوشی با کابل USB و فعال‌سازی USB Debugging
flutter install

# یا کپی فایل APK به گوشی:
# build/app/outputs/flutter-apk/app-release.apk
```

---

## ساختار فایل‌های پروژه

```
lib/
├── main.dart                          ← نقطه شروع اپ
├── models/
│   └── remote_mode.dart               ← تعریف حالت‌ها (BT/IR)
├── screens/
│   ├── welcome_screen.dart            ← صفحه خوش‌آمد
│   ├── size_picker_screen.dart        ← انتخاب اندازه کنترل
│   ├── remote_screen.dart             ← صفحه اصلی کنترل
│   └── bt_debug_screen.dart          ← 🆕 Debug دکمه‌های ریموت فیزیکی
├── services/
│   ├── ir_codes.dart                  ← کدهای IR (⚠️ نیاز به جایگزینی)
│   ├── ir_service.dart                ← پل Dart↔Kotlin برای IR
│   ├── bluetooth_service.dart         ← سرویس BLE
│   ├── remote_controller.dart         ← هماهنگ‌کننده IR/BT
│   └── remote_input_handler.dart     ← 🆕 نگاشت ریموت فیزیکی HID
├── widgets/
│   ├── remote_button.dart             ← دکمه با انیمیشن
│   └── touchpad.dart                  ← تاچ‌پد موس
└── theme/
    └── colors.dart                    ← پالت رنگی

android/
├── build.gradle                       ← تنظیمات اصلی Gradle
├── settings.gradle                    ← نام پروژه
├── gradle.properties                  ← تنظیمات حافظه
├── gradle/wrapper/
│   ├── gradle-wrapper.properties      ← نسخه Gradle
│   └── gradle-wrapper.jar             ← [از SETUP.sh گرفته می‌شود]
├── gradlew                            ← [از SETUP.sh گرفته می‌شود]
└── app/
    ├── build.gradle                   ← تنظیمات اپ (SDK، packageId)
    └── src/main/
        ├── AndroidManifest.xml        ← مجوزها
        ├── kotlin/.../MainActivity.kt ← کانال IR نیتیو
        └── res/mipmap-*/              ← آیکون اپ
```

---

## بعد از build — دو چیز برای تست کامل

### ۱. کدهای IR واقعی
فایل `lib/services/ir_codes.dart` را باز کنید و اعداد hex هر دکمه را
با کدهای واقعی ریموت دوو مدل ۱۳۶۳ جایگزین کنید.

**ابزار پیشنهادی:** اپ «IRplus» یا «SURE Universal Remote» روی گوشی Android

### ۲. UUID بلوتوث (اگر حالت BLE استفاده می‌کنید)
فایل `lib/services/bluetooth_service.dart` — مقادیر `serviceUuid` و `writeCharUuid`
را با UUID واقعی کنترل دوو جایگزین کنید.

**ابزار پیشنهادی:** اپ «nRF Connect» (رایگان در گوگل‌پلی)

---

## شناسایی دکمه‌های ریموت فیزیکی بلوتوثی (HID)

1. APK را نصب کنید
2. ریموت فیزیکی دوو را از **تنظیمات گوشی → بلوتوث** Pair کنید
3. اپ را باز کنید → حالت بلوتوثی → آیکون 🪲 در بالا
4. هر دکمه را فشار دهید — کد آن نمایش داده می‌شود
5. کد را در `remote_input_handler.dart → customKeyMap` بنویسید
