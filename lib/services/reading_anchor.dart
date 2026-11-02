class ReadingAnchor {
  static ({int start, int end})? resolve(
    String text,
    String selected, {
    int? startOffset,
    int? endOffset,
    String before = '',
    String after = '',
  }) {
    if (selected.isEmpty) return null;
    final matches = <({int start, int end})>[];
    var from = 0;
    while (from <= text.length) {
      final start = text.indexOf(selected, from);
      if (start < 0) break;
      final end = start + selected.length;
      if ((before.isEmpty || text.substring(0, start).endsWith(before)) &&
          (after.isEmpty || text.substring(end).startsWith(after))) {
        matches.add((start: start, end: end));
      }
      from = start + 1;
    }
    if (startOffset != null && endOffset != null) {
      for (final match in matches) {
        if (match.start == startOffset && match.end == endOffset) return match;
      }
    }
    return matches.length == 1 ? matches.single : null;
  }
}
