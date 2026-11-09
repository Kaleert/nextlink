import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/vpn_readiness.dart';

void main() {
  test(
    'waits for Android service and TUN instead of failing on an alive core',
    () async {
      final samples = [
        {'status': 'stopped', 'coreRunning': true},
        {'status': 'starting', 'coreRunning': true},
        {'status': 'starting', 'coreRunning': true},
        {'status': 'connected', 'coreRunning': true},
      ];
      var reads = 0;
      final result = await waitForVpnReadiness(
        readSnapshot: () async => samples[reads++],
        isCancelled: () => false,
        pollInterval: Duration.zero,
      );
      expect(result, VpnReadiness.ready);
      expect(reads, 4);
    },
  );
  test(
    'core crash fails without claiming that a pending tunnel was ready',
    () async {
      var reads = 0;
      final result = await waitForVpnReadiness(
        readSnapshot: () async => ++reads == 1
            ? {'status': 'starting', 'coreRunning': true}
            : {'status': 'stopped', 'coreRunning': false},
        isCancelled: () => false,
        pollInterval: Duration.zero,
      );
      expect(result, VpnReadiness.stopped);
    },
  );
  test(
    'cancellation stops waiting before sending another native request',
    () async {
      final result = await waitForVpnReadiness(
        readSnapshot: () async => throw StateError('must not be called'),
        isCancelled: () => true,
      );
      expect(result, VpnReadiness.cancelled);
    },
  );
  test('a stalled start has a bounded timeout', () async {
    final result = await waitForVpnReadiness(
      readSnapshot: () async => {'status': 'starting', 'coreRunning': true},
      isCancelled: () => false,
      timeout: const Duration(milliseconds: 30),
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(result, VpnReadiness.timedOut);
  });
}
