/// نوع اتصال کنترل: بلوتوث یا فرستنده مادون‌قرمز (IR)
enum RemoteMode { bluetooth, ir }

/// اندازه کنترل: بزرگ (تمام قابلیت‌ها) یا کوچک (جمع‌وجور، با موس/میکروفون فقط در حالت بلوتوث)
enum RemoteSize { large, small }

extension RemoteModeX on RemoteMode {
  bool get isBluetooth => this == RemoteMode.bluetooth;
  bool get isIr => this == RemoteMode.ir;

  String get title => isBluetooth ? 'بلوتوث' : 'فرستنده IR';

  /// در حالت IR، موس لمسی و ضبط صدا غیرفعال است چون IR یک‌طرفه است
  /// و سخت‌افزار میکروفون/موس فقط داخل کنترل بلوتوثی کوچک دوو وجود دارد.
  bool get supportsMouseAndMic => isBluetooth;
}
