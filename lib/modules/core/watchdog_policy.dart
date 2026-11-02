/// Decides when a live tunnel must be declared dead.
///
/// The data plane is sampled periodically, not continuously: one missed probe
/// can be a handover, a brief radio stall, or a probe host under load. Two
/// consecutive misses (about 40 seconds at the controller's cadence) are the
/// drop threshold; any success resets the count, so a tunnel that recovers on
/// its own is never torn down.
class WatchdogPolicy {
  WatchdogPolicy({this.missesToDrop = 2});

  final int missesToDrop;

  int _misses = 0;
  bool _verified = false;

  int get misses => _misses;

  /// True once any probe succeeded on the current session.
  bool get verified => _verified;

  void reset() {
    _misses = 0;
    _verified = false;
  }

  /// Records one probe result and returns true when the session must be
  /// dropped and redialled.
  bool record({required bool ok}) {
    if (ok) {
      _misses = 0;
      _verified = true;
      return false;
    }
    _misses++;
    return _misses >= missesToDrop;
  }
}
