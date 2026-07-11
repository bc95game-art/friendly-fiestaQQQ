/// نوع اتصال کنترل: بلوتوث یا فرستنده مادون‌قرمز (IR)
enum RemoteMode { bluetooth, ir }

/// اندازه کنترل: بزرگ (تمام قابلیت‌ها) یا کوچک (جمع‌وجور، با تاچ‌پد موس فقط در حالت بلوتوث)
enum RemoteSize { large, small }

extension RemoteModeX on RemoteMode {
  bool get isBluetooth => this == RemoteMode.bluetooth;
  bool get isIr => this == RemoteMode.ir;

  String get title => isBluetooth ? 'بلوتوث' : 'فرستنده IR';

  /// تاچ‌پد موس فقط در حالت بلوتوث معنا دارد، چون از پروفایل HID موس
  /// واقعی برای حرکت اشاره‌گر روی تلویزیون استفاده می‌کند؛ IR یک‌طرفه
  /// است و چنین قابلیتی ندارد.
  bool get supportsTouchpad => isBluetooth;
}
