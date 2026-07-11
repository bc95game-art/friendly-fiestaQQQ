#!/bin/bash
# ══════════════════════════════════════════════════════════════════
#  اسکریپت آماده‌سازی پروژه Daewoo Remote Pro برای build
#  فقط یک بار اجرا کنید — بعد از آن مستقیم flutter build apk بزنید
# ══════════════════════════════════════════════════════════════════

set -e

echo "🔧 مرحله ۱: بررسی Flutter..."
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter پیدا نشد. ابتدا Flutter SDK نصب کنید:"
    echo "   https://docs.flutter.dev/get-started/install/linux"
    exit 1
fi
flutter --version

echo ""
echo "🔧 مرحله ۲: ساخت پروژه موقت برای گرفتن فایل‌های Gradle..."
TEMP_DIR="/tmp/daewoo_flutter_temp"
rm -rf "$TEMP_DIR"
flutter create --org ali.khaleghi --project-name daewoo_remote_pro "$TEMP_DIR"

echo ""
echo "🔧 مرحله ۳: کپی فایل‌های باینری Gradle (gradle-wrapper.jar, gradlew)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$TEMP_DIR/android/gradlew"                           "$SCRIPT_DIR/android/gradlew"
cp "$TEMP_DIR/android/gradlew.bat"                       "$SCRIPT_DIR/android/gradlew.bat"
cp "$TEMP_DIR/android/gradle/wrapper/gradle-wrapper.jar" "$SCRIPT_DIR/android/gradle/wrapper/gradle-wrapper.jar"

chmod +x "$SCRIPT_DIR/android/gradlew"

echo ""
echo "🔧 مرحله ۴: نصب dependencies..."
cd "$SCRIPT_DIR"
flutter pub get

echo ""
echo "✅ آماده است! حالا می‌توانید APK بسازید:"
echo ""
echo "   # نسخه debug (سریع‌تر، برای تست):"
echo "   flutter build apk --debug"
echo ""
echo "   # نسخه release (برای استفاده نهایی):"
echo "   flutter build apk --release"
echo ""
echo "   # فایل APK در این مسیر قرار می‌گیرد:"
echo "   build/app/outputs/flutter-apk/app-release.apk"
echo ""
rm -rf "$TEMP_DIR"
echo "🧹 پروژه موقت پاک شد."
