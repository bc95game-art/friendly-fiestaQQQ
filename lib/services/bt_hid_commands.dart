/// نگاشت دکمه‌های منطقی کنترل به کدهای استاندارد USB-HID.
///
/// این پروژه به‌جای اختراع یک پروتکل اختصاصی (که چون UUID/فرمت واقعی
/// کنترل بلوتوثی دوو در دسترس نیست، قابل تضمین نبود)، از استاندارد رسمی
/// Bluetooth HID Device استفاده می‌کند: گوشی مستقیماً خودش را به‌عنوان یک
/// «کیبورد/کنترل چندرسانه‌ای بلوتوثی» به تلویزیون معرفی می‌کند — دقیقاً
/// همان چیزی که ریموت فیزیکی HID دوو (که کدهایش در RemoteScreen قبلاً
/// شناسایی شده بود: ArrowLeft/ArrowRight/MediaPlayPause) انجام می‌دهد.
/// چون تلویزیون شما یک Android TV واقعی است (مدل ۴۳DSL، اندروید ۹)، این
/// روش دقیقاً همان چیزی است که کیبورد/ریموت بلوتوثی استاندارد با آن کار
/// می‌کند و نیازی به کشف UUID اختصاصی ندارد.
library bt_hid_commands;

/// یک ورودی نگاشت: صفحه‌ی HID (Consumer یا Keyboard) + کد Usage
class BtHidCommand {
  /// true = Consumer Control Page (0x0C)، false = Keyboard Page (0x07)
  final bool consumer;
  final int usage;
  const BtHidCommand(this.consumer, this.usage);
}

class BtHidCommands {
  BtHidCommands._();

  /// فقط دکمه‌هایی که کد Usage استاندارد و پشتیبانی‌شده‌ی گسترده دارند اینجا
  /// نگاشت شده‌اند. دکمه‌هایی که اینجا نیستند (مثل دکمه‌های رنگی یا EPG) در
  /// حالت بلوتوث با پیام صریح «پشتیبانی نمی‌شود» مواجه می‌شوند — نه با شکست
  /// خاموش — و باید از حالت فرستنده IR استفاده شوند.
  static const Map<String, BtHidCommand> map = {
    'power': BtHidCommand(true, 0x0030), // Power
    'mute': BtHidCommand(true, 0x00E2), // Mute
    'vol_up': BtHidCommand(true, 0x00E9), // Volume Increment
    'vol_down': BtHidCommand(true, 0x00EA), // Volume Decrement
    'ch_up': BtHidCommand(true, 0x009C), // Channel Increment
    'ch_down': BtHidCommand(true, 0x009D), // Channel Decrement
    'home': BtHidCommand(true, 0x0223), // AC Home
    'back': BtHidCommand(true, 0x0224), // AC Back
    'menu': BtHidCommand(true, 0x0040), // Menu
    'exit': BtHidCommand(true, 0x0046), // Menu Escape
    'ok': BtHidCommand(true, 0x0041), // Menu Pick
    'up': BtHidCommand(true, 0x0042), // Menu Up
    'down': BtHidCommand(true, 0x0043), // Menu Down
    'left': BtHidCommand(true, 0x0044), // Menu Left
    'right': BtHidCommand(true, 0x0045), // Menu Right
    'play_pause': BtHidCommand(true, 0x00CD), // Play/Pause
    'rewind': BtHidCommand(true, 0x00B4), // Rewind
    'forward': BtHidCommand(true, 0x00B3), // Fast Forward
    // ⚠️ باگ رفع‌شده: کد قبلی «info» به‌اشتباه 0x0061 بود که در واقع کد
    // Closed Caption (زیرنویس) است، نه Data On Screen. بر اساس جدول واقعی
    // هسته لینوکس (drivers/hid/hid-input.c) که این کدها را به کلید واقعی
    // اندروید تبدیل می‌کند: 0x060=Data On Screen (info) و 0x061=Closed
    // Caption (subtitle) — این دو دقیقاً برعکس هم در کد قبلی بودند.
    'info': BtHidCommand(true, 0x0060), // Data On Screen
    'subtitle': BtHidCommand(true, 0x0061), // Closed Caption
    // منبع کدهای زیر: drivers/hid/hid-input.c (پروژه لینوکس، متن‌باز و
    // عمومی) — همان جدولی که اندروید برای تبدیل کد HID به دکمه واقعی
    // (KEY_RED/GREEN/BLUE/YELLOW/PROGRAM/ASPECT_RATIO/AUDIO_TRACK) استفاده
    // می‌کند. این‌ها حدسی نیستند، از سورس‌کد واقعی هسته استخراج شده‌اند.
    'color_red': BtHidCommand(true, 0x0069),    // KEY_RED
    'color_green': BtHidCommand(true, 0x006A),  // KEY_GREEN
    // ⚠️ رفع باگ «رنگ‌ها جابجا»: قبلاً blue=0x006B و yellow=0x006C بود که
    // برعکس جدول واقعی hid-input.c (پروژه لینوکس) است — آن جدول صراحتاً
    // 0x006B=KEY_YELLOW و 0x006C=KEY_BLUE تعریف می‌کند. حالا تصحیح شد.
    'color_yellow': BtHidCommand(true, 0x006B), // KEY_YELLOW (hid-input.c)
    'color_blue': BtHidCommand(true, 0x006C),   // KEY_BLUE   (hid-input.c)
    'epg': BtHidCommand(true, 0x008D), // Program Guide
    // «Zoom» دکمه‌ی تکی‌ست (نه Zoom In/Out جداگانه)، نزدیک‌ترین معادل واقعی
    // آن در جدول استاندارد Aspect Ratio (تعویض حالت نمایش/زوم) است.
    'zoom': BtHidCommand(true, 0x006D), // Aspect Ratio
    'audio_track': BtHidCommand(true, 0x0173), // Media Audio Track
    'mic': BtHidCommand(true, 0x00CF), // Voice Command (دکمه میکروفون کنترل کوچک)
    'prev': BtHidCommand(true, 0x00B6), // Scan Previous Track
    'next': BtHidCommand(true, 0x00B5), // Scan Next Track
    'stop': BtHidCommand(true, 0x00B7), // Stop
    'record': BtHidCommand(true, 0x00B2), // Record
    // پیدا شد در بازبینی نهایی: دکمه «Return» کی‌پد در حالت بلوتوث اصلاً
    // نگاشت نداشت (فقط IR داشت) — با کد استاندارد کیبورد Enter (صفحه‌ی
    // Keyboard/Keypad، Usage 0x28) اضافه شد.
    'return': BtHidCommand(false, 0x28), // Keyboard Enter/Return
    'num_0': BtHidCommand(false, 0x27),
    'num_1': BtHidCommand(false, 0x1E),
    'num_2': BtHidCommand(false, 0x1F),
    'num_3': BtHidCommand(false, 0x20),
    'num_4': BtHidCommand(false, 0x21),
    'num_5': BtHidCommand(false, 0x22),
    'num_6': BtHidCommand(false, 0x23),
    'num_7': BtHidCommand(false, 0x24),
    'num_8': BtHidCommand(false, 0x25),
    'num_9': BtHidCommand(false, 0x26),
    // ⚠️ رفع باگ «source خارج از map»: در کامیت قبلی source اشتباهاً بعد از
    // بسته‌شدن آکولاد map گذاشته شد (compile error). حالا در جای درست است.
    // HID Consumer 0x0089 = «Media Select TV» → KEYCODE_TV_INPUT در Android TV
    // که دیالوگ «انتخاب منبع ورودی» (HDMI1/HDMI2/...) را باز می‌کند.
    'source': BtHidCommand(true, 0x0089),
  };

  /// دکمه‌هایی که در حالت BT فیزیکاً غیرممکن هستند — فقط از طریق IR
  /// به سخت‌افزار TV دسترسی دارند و Android TV آنها را از BT HID نمی‌پذیرد.
  /// در Android Generic.kl این کدها (#key 385 KEY_RADIO / #key 388 KEY_TEXT)
  /// comment‌شده‌اند یعنی هیچ HID Consumer code‌ای به آنها نگاشت نمی‌شود.
  /// UI در حالت BT این دکمه‌ها را با برچسب «فقط IR» غیرفعال نشان می‌دهد.
  static const Set<String> irOnlyKeys = {'text', 'radio', 'shift'};
}
