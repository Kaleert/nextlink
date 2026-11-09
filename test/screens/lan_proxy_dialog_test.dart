import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/screens/lan_proxy_dialog.dart';

void main() {
  testWidgets('LAN form validates and returns port, username, and password', (
    tester,
  ) async {
    SettingsState? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<SettingsState>(
                  context: context,
                  builder: (_) => LanProxyDialog(settings: SettingsState()),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '10808');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('Порт LAN занят'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2080');
    await tester.enterText(find.byType(TextField).at(1), 'alice');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      true,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(result!.lanUsername, 'alice');
    expect(result!.lanPassword, 'secret');
    expect(result!.lanPort, 2080);
    expect(tester.takeException(), isNull);
  });
}
