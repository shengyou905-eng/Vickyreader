class LatestRequestGuard {
  int _version = 0;

  int begin() => ++_version;

  bool isCurrent(int version) => version == _version;

  void invalidate() {
    _version++;
  }
}
