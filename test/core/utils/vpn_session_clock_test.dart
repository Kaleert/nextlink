import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/vpn_session_clock.dart';

void main() {
  test('repeated native samples cannot rewind a session; a new connection resets it', () {
    final clock = VpnSessionClock();
    clock.sync(session: 'first', elapsedMs: 12500, running: true);
    clock.sync(session: 'first', elapsedMs: 12000, running: true);
    expect(clock.elapsedSeconds, 12);
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(12500));
    clock.sync(session: 'second', elapsedMs: 500, running: true);
    expect(clock.elapsedSeconds, 0);
    clock.sync(session: 'second', elapsedMs: 4000, running: true);
    expect(clock.elapsedSeconds, 4);
  });
  test('pause freezes time across duplicate samples, resume retains accumulated time', () async {
    final clock = VpnSessionClock();
    clock.sync(session: 'vpn', elapsedMs: 10200, running: true);
    clock.sync(session: 'vpn', elapsedMs: 10100, running: false);
    final paused = clock.elapsedMilliseconds;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(clock.elapsedMilliseconds, paused);
    clock.sync(session: 'vpn', elapsedMs: 10000, running: false);
    expect(clock.elapsedMilliseconds, paused);
    clock.sync(session: 'vpn', elapsedMs: 10250, running: true);
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(paused));
    clock.reset();
    expect(clock.elapsedSeconds, 0);
  });
}
