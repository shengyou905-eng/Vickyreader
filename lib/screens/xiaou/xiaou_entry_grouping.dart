String normalizeXiaouBookTitle(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'^[《〈]+|[》〉]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
}

String xiaouBookGroupKey(Map<String, dynamic> item) {
  final title = item['book_title']?.toString() ?? '';
  final normalizedTitle = normalizeXiaouBookTitle(title);
  if (normalizedTitle.isNotEmpty) return 'title:$normalizedTitle';

  final id = item['book_id']?.toString().trim() ?? '';
  return id.isEmpty ? 'book:unknown' : 'id:$id';
}

bool xiaouEntryBelongsToBook(
  Map<String, dynamic> item, {
  required String bookId,
  required String bookTitle,
}) {
  final normalizedTarget = normalizeXiaouBookTitle(bookTitle);
  if (normalizedTarget.isNotEmpty) {
    return normalizeXiaouBookTitle(item['book_title']?.toString() ?? '') ==
        normalizedTarget;
  }
  return bookId.isNotEmpty && item['book_id']?.toString().trim() == bookId;
}
