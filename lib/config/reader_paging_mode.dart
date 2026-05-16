/// EPUB/TXT 在 WebView 中的滚动轴向；PDF 的 [PdfView.scrollDirection] 与之对齐。
enum ReaderPagingMode {
  /// 纵向连续滚动
  vertical,

  /// 横向：WebView 为多栏左右滑；PDF 为横向逐页
  horizontal;

  static ReaderPagingMode fromStorage(String? raw) {
    switch (raw) {
      case 'horizontal':
      case 'swipe': // 旧版式键兼容
        return ReaderPagingMode.horizontal;
      case 'vertical':
      case 'scroll':
      default:
        return ReaderPagingMode.vertical;
    }
  }

  String get storageValue => name;
}
