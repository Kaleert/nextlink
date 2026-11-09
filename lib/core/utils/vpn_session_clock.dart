/// Interpolates native elapsed time with a monotonic clock, never wall time or
/// accumulated Timer ticks. Old samples cannot rewind an active session.
class VpnSessionClock {
  final Stopwatch _watch = Stopwatch();
  String? _session;
  int _baseMs = 0;
  bool _running = false;

  int get elapsedMilliseconds =>
      _baseMs + (_running ? _watch.elapsedMilliseconds : 0);
  int get elapsedSeconds => elapsedMilliseconds ~/ 1000;

  void sync({
    required String session,
    required int elapsedMs,
    required bool running,
  }) {
    final sameSession = _session == session;
    final current = sameSession ? elapsedMilliseconds : 0;
    _session = session;
    _baseMs = sameSession
        ? (elapsedMs > current ? elapsedMs : current)
        : elapsedMs.clamp(0, 1 << 62);
    _running = running;
    _watch..reset();
    if (running) {
      _watch.start();
    } else {
      _watch.stop();
    }
  }

  void reset() {
    _session = null;
    _baseMs = 0;
    _running = false;
    _watch
      ..stop()
      ..reset();
  }
}
