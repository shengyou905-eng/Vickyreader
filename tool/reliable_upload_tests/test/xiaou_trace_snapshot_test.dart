import '../../../test/services/xiaou_trace_snapshot_test.dart' as snapshot;
import '../../../test/widgets/xiaou_card_test.dart' as cards;
import '../../../test/screens/xiaou_entry_grouping_test.dart' as grouping;
import '../../../test/widgets/xiaou_keyboard_layout_test.dart' as keyboard;
import '../../../test/widgets/xiaou_swipe_actions_test.dart' as swipe;
import '../../../test/widgets/xiaou_topic_theme_test.dart' as topics;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('read-only trace snapshot', snapshot.main);
  group('trace cards', cards.main);
  group('trace grouping', grouping.main);
  group('keyboard layout', keyboard.main);
  group('trace actions', swipe.main);
  group('topic layout', topics.main);
}
