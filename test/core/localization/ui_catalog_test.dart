import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/localization/app_localizations.dart';

class _UiKeys extends RecursiveAstVisitor<void> {
  final values = <String>{};
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target?.toSource() == 'AppLocalizations' &&
        node.methodName.name == 'text') {
      final args = node.argumentList.arguments;
      if (args.length > 1 && args[1] is SimpleStringLiteral) {
        final value = (args[1] as SimpleStringLiteral).value;
        if (RegExp('[А-Яа-яЁё]').hasMatch(value)) values.add(value);
      }
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RU/UK/EN cover presentation keys and retain format arguments', () {
    final catalogs = {
      for (final lang in ['ru', 'uk', 'en'])
        lang: Map<String, String>.from(
          jsonDecode(File('assets/lang/ui_$lang.json').readAsStringSync())
              as Map,
        ),
    };
    final collector = _UiKeys();
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart'))
        parseString(content: file.readAsStringSync()).unit.accept(collector);
    }
    final tokens = RegExp(r'\{\{\w+\}\}|\{\d+\}');
    Set<String> placeholders(String s) =>
        tokens.allMatches(s).map((m) => m[0]!).toSet();
    for (final lang in catalogs.keys) {
      expect(
        collector.values.difference(catalogs[lang]!.keys.toSet()),
        isEmpty,
        reason: lang,
      );
      expect(catalogs[lang]!.keys.toSet(), catalogs['ru']!.keys.toSet());
      for (final entry in catalogs[lang]!.entries) {
        expect(
          placeholders(entry.value),
          placeholders(entry.key),
          reason: '$lang: ${entry.key}',
        );
      }
    }
  });
  test(
    'formatted values stay literal even when they look like placeholders',
    () {
      expect(
        AppLocalizations.format(
          {'Источник {0} / {1}': 'Source {0} / {1}'},
          'Источник {0} / {1}',
          ['My {1} server', 42],
        ),
        'Source My {1} server / 42',
      );
    },
  );
  test('background notification catalog follows selected language', () async {
    final en = await AppLocalizations.uiCatalog('en');
    expect(
      AppLocalizations.format(en, 'Загрузка {0}', ['Xray']),
      'Downloading Xray',
    );
    final uk = await AppLocalizations.uiCatalog('uk');
    expect(AppLocalizations.format(uk, 'Продолжить', []), 'Продовжити');
  });
}
