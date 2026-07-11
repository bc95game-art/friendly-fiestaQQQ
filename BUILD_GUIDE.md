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
│   └── remote_screen.dart             ← صفحه اصلی کنترل
├── services/
│   ├── ir_codes.dart                  ← کدهای IR (برخی دکمه‌ها هنوز نیاز به ضبط دارند)
│   ├── ir_service.dart                ← پل Dart↔Kotlin برای IR
│   ├── bt_hid_service.dart            ← پل بلوتوث HID واقعی (کیبورد/موس/کنترل چندرسانه‌ای)
│   ├── bt_hid_commands.dart           ← نگاشت دکمه‌ها به کدهای استاندارد HID
│   └── remote_controller.dart         ← هماهنگ‌کننده IR/BT
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

## بعد از build

### ۱. استفاده از حالت بلوتوث
1. APK را نصب کنید
2. از **تنظیمات گوشی → بلوتوث**، بلوتوث تلویزیون را Pair کنید (مثل هر دستگاه دیگر)
3. داخل اپ → حالت بلوتوثی → از لیست دستگاه‌های Pair‌شده، تلویزیون را انتخاب کنید
4. اپ با پروفایل استاندارد `BluetoothHidDevice` مستقیماً به تلویزیون وصل می‌شود و
   دکمه‌ها را مثل یک کیبورد/ریموت بلوتوثی واقعی ارسال می‌کند — بدون نیاز به هیچ
   UUID یا ابزار کشف جانبی (nRF Connect دیگر لازم نیست).

### ۲. کدهای IR واقعی (اختیاری — برای فعال‌سازی دکمه‌های باقی‌مانده در حالت IR)
فایل `lib/services/ir_codes.dart` را باز کنید و در صورت نیاز، کدهای بیشتری با یک
گیرنده IR واقعی ضبط و اضافه کنید.

**ابزار پیشنهادی:** اپ «IRplus» یا «SURE Universal Remote» روی گوشی Android
