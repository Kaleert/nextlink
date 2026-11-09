import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/shared/widgets/adaptive_home_header.dart';

void main() {
  for (final width in [260.0, 360.0, 600.0]) {
    testWidgets('header keeps actions at trailing edge at width $width', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: AdaptiveHomeHeader(
                key: const ValueKey('header'),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'NextLink',
                      style: TextStyle(fontSize: 34, fontFamily: 'monospace'),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
                actions: Row(
                  key: const ValueKey('actions'),
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (_) => IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.settings),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('actions'))).right,
        closeTo(tester.getRect(find.byKey(const ValueKey('header'))).right, .1),
      );
    });
  }
}
