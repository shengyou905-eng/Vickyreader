enum ReaderFontFamily {
  system,
  serif,
  wenkai;

  String get storageValue => name;

  String get label => switch (this) {
    ReaderFontFamily.system => '默认',
    ReaderFontFamily.serif => '宋体',
    ReaderFontFamily.wenkai => '文楷',
  };

  String get description => switch (this) {
    ReaderFontFamily.system => '清晰自然',
    ReaderFontFamily.serif => '沉静书页',
    ReaderFontFamily.wenkai => '温润手写',
  };

  String? get previewFontFamily => switch (this) {
    ReaderFontFamily.system => null,
    ReaderFontFamily.serif => 'SourceHanSerifCN',
    ReaderFontFamily.wenkai => 'LXGWWenKaiLite',
  };

  List<String>? get previewFontFallback => switch (this) {
    ReaderFontFamily.system => null,
    ReaderFontFamily.serif => const [
      'Songti SC',
      'STSong',
      'Noto Serif CJK SC',
      'Noto Serif SC',
      'serif',
    ],
    ReaderFontFamily.wenkai => const [
      'Kaiti SC',
      'STKaiti',
      'KaiTi',
      'PingFang SC',
      'sans-serif',
    ],
  };

  String get cssStack => switch (this) {
    ReaderFontFamily.system =>
      '-apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif',
    ReaderFontFamily.serif =>
      '"ZhiDu Source Han Serif", "Songti SC", "STSong", "Noto Serif CJK SC", serif',
    ReaderFontFamily.wenkai =>
      '"LXGW WenKai Lite", "Kaiti SC", "STKaiti", "KaiTi", "PingFang SC", sans-serif',
  };

  static ReaderFontFamily fromStorage(String? value) {
    return ReaderFontFamily.values.firstWhere(
      (font) => font.storageValue == value,
      orElse: () => ReaderFontFamily.system,
    );
  }
}

class ReaderTypographyDefaults {
  ReaderTypographyDefaults._();

  static const fontFamily = ReaderFontFamily.system;
  static const fontSize = 18.0;
  static const lineHeight = 1.6;
  static const pageMargin = 18.0;
}
