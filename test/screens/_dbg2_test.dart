import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debug raw overlay insert', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final nav = Navigator.of(context, rootNavigator: true);
                // ignore: avoid_print
                print('NAV=${nav.runtimeType} overlay=${nav.overlay}');
                nav.overlay!.insert(
                  OverlayEntry(builder: (_) => const Text('HELLO')),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('HELLO found=${find.text('HELLO').evaluate().length}');
  });
}
