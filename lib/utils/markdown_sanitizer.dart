String stripMarkdownMarkers(String input) {
  if (input.isEmpty) return input;

  var text = input;
  text = text.replaceAllMapped(
    RegExp(r'\*\*\*(.+?)\*\*\*', dotAll: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*', dotAll: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'__(.+?)__', dotAll: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`', dotAll: true),
    (match) => match.group(1) ?? '',
  );

  return text
      .replaceAll(RegExp(r'(^|\n)\s{0,3}#{1,6}\s+'), r'$1')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .trimRight();
}
