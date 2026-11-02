import '../../../test/services/reading_trace_transaction_test.dart' as atomic;
import '../../../test/services/ai_protocol_test.dart' as protocol;
import '../../../test/services/reading_anchor_test.dart' as anchors;
import '../../../test/providers/ai_reliability_test.dart' as provider;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P0a atomic local persistence', atomic.main);
  group('P0a stream and evidence protocol', protocol.main);
  group('P0a reading anchors', anchors.main);
  group('P0a provider integration', provider.main);
}
