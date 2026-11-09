import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/providers/stats_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('durable checkpoints replay once, retain their date, and separate networks', () async {
    SharedPreferences.setMockInitialValues({});
    var stats = StatsNotifier();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await stats.updateFromNative(
      100,
      20,
      sessionId: 'vpn/0',
      isWifi: true,
      appBytes: {'app.one': 120},
      timestamp: yesterday,
    );
    stats.dispose();
    stats = StatsNotifier();
    // Crash between persisting the counters and acknowledging the checkpoint.
    await stats.updateFromNative(
      100,
      20,
      sessionId: 'vpn/0',
      isWifi: true,
      appBytes: {'app.one': 120},
      timestamp: yesterday,
    );
    await stats.updateFromNative(
      150,
      30,
      sessionId: 'vpn/0',
      isWifi: true,
      appBytes: {'app.one': 180},
      timestamp: yesterday,
    );
    await stats.updateFromNative(
      40,
      10,
      sessionId: 'vpn/1',
      isMobile: true,
      appBytes: {'app.two': 50},
    );
    expect(stats.state.lifetimeWifiRx, 150);
    expect(stats.state.lifetimeWifiTx, 30);
    expect(stats.state.lifetimeMobileRx, 40);
    expect(stats.state.lifetimeMobileTx, 10);
    expect(stats.state.appBytesMap, {'app.one': 180, 'app.two': 50});
    final key =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    expect(stats.state.dailyRecords[key]!.total, 180);
    stats.dispose();
  });
}
