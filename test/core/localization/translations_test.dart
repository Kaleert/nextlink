import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['ru', 'uk', 'en']) {
    test(
      '$language contains every literal translation key used by the client',
      () {
        final keys = <String>{};
        final pattern = RegExp(r'''\.translate\(\s*['"]([^'"]+)['"]''');
        for (final file in Directory(
          'lib',
        ).listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          keys.addAll(
            pattern.allMatches(file.readAsStringSync()).map((m) => m[1]!),
          );
        }
        final translations = jsonDecode(
          File('assets/lang/$language.json').readAsStringSync(),
        ) as Map;
        expect(
          keys.difference(translations.keys.cast<String>().toSet()),
          isEmpty,
        );
        expect(translations['core_failover'], isNot('core_failover'));
      },
    );
  }
}
