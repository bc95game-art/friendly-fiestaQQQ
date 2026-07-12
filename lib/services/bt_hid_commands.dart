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
    'color_red': BtHidCommand(true, 0x0069),
    'color_green': BtHidCommand(true, 0x006A),
    'color_blue': BtHidCommand(true, 0x006B),
    'color_yellow': BtHidCommand(true, 0x006C),
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
  };

  // ⚠️ عمداً نگاشت نشده‌اند (چون کد استاندارد و تضمینی برای آن‌ها در جدول
  // رسمی HID/هسته لینوکس پیدا نشد — به‌جای حدس زدن، پیام صریح «پشتیبانی
  // نمی‌شود» نمایش داده می‌شود):
  //  • text (تلتکست): هیچ کد استاندارد Consumer برای Teletext وجود ندارد.
  //  • radio: کد اختصاصی «رادیو» در جدول استاندارد نیست (فقط Tuner/TV عمومی
  //    هست که معادل دقیق رادیوی دوو نیست).
  //  • shift: در ریموت اصلی یک کلید ثانویه‌ی اعداد/نمادهاست، نه Shift
  //    کیبورد استاندارد — بدون کد ضبط‌شده‌ی واقعی نمی‌توان آن را حدس زد.
  //  • source: هیچ کد Consumer استاندارد و به‌طور گسترده پشتیبانی‌شده برای
  //    تعویض منبع ورودی روی Android TV وجود ندارد.
}
