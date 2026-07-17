/// نوع اتصال کنترل: بلوتوث، فرستنده مادون‌قرمز (IR)، یا وای‌فای
enum RemoteMode { bluetooth, ir, wifi }

/// اندازه کنترل: بزرگ (قابلیت‌های بیشتر) یا کوچک (جمع‌وجور با تاچ‌پد)
enum RemoteSize { large, small }

extension RemoteModeX on RemoteMode {
  bool get isBluetooth => this == RemoteMode.bluetooth;
  bool get isIr        => this == RemoteMode.ir;
  bool get isWifi      => this == RemoteMode.wifi;

  String get title => switch (this) {
    RemoteMode.bluetooth => 'بلوتوث',
    RemoteMode.ir        => 'فرستنده IR',
    RemoteMode.wifi      => 'وای‌فای',
  };

  /// تاچ‌پد موس در هر دو حالت بلوتوث و وای‌فای معنا دارد.
  /// IR یک‌طرفه است و از حرکت نشانگر پشتیبانی نمی‌کند.
  bool get supportsTouchpad => isBluetooth || isWifi;
}
