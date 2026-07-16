import 'package:ai_reader/screens/xiaou/xiaou_entry_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('re-imported copies with different ids share one book group', () {
    final first = <String, dynamic>{
      'book_id': 'import-1',
      'book_title': '西方哲学史',
    };
    final second = <String, dynamic>{
      'book_id': 'import-2',
      'book_title': '  《西方哲学史》 ',
    };

    expect(xiaouBookGroupKey(first), xiaouBookGroupKey(second));
    expect(
      xiaouEntryBelongsToBook(second, bookId: '', bookTitle: '西方哲学史'),
      isTrue,
    );
  });
}
