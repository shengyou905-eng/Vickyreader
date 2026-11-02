import '../../../test/services/ai_account_isolation_test.dart' as isolation;
import '../../../test/services/ai_ownership_migration_test.dart' as migration;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI ownership migration', migration.main);
  group('AI account isolation', isolation.main);
}
