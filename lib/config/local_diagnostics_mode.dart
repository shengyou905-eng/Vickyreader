/// Compile-time only. No persisted switch, pause marker, or runtime override.
class LocalDiagnosticsMode {
  static const enabled = bool.fromEnvironment('ENABLE_LOCAL_SYNC_DIAGNOSTICS');

  static void requireBusinessWritesAllowed() {
    if (enabled) {
      throw StateError('Business database access is disabled in evidence mode');
    }
  }
}
