import 'dart:async';

enum VpnReadiness { ready, stopped, timedOut, cancelled }

/// The core can be alive while Android is still creating its service and TUN.
/// A temporarily stopped/missing service is not evidence that the core exited.
Future<VpnReadiness> waitForVpnReadiness({
  required Future<Map<String, dynamic>> Function() readSnapshot,
  required bool Function() isCancelled,
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final watch = Stopwatch()..start();
  var sawStarting = false;
  while (watch.elapsed < timeout) {
    if (isCancelled()) return VpnReadiness.cancelled;
    final snapshot = await readSnapshot();
    if (isCancelled()) return VpnReadiness.cancelled;
    if (snapshot['coreRunning'] == false) return VpnReadiness.stopped;
    switch (snapshot['status']) {
      case 'connected':
        return VpnReadiness.ready;
      case 'starting':
        sawStarting = true;
        break;
      case 'paused':
        return VpnReadiness.stopped;
      case 'stopped':
        if (sawStarting) return VpnReadiness.stopped;
        break;
    }
    await Future<void>.delayed(pollInterval);
  }
  return VpnReadiness.timedOut;
}
