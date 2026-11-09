import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Change {
  final int at, length;
  final String text;
  Change(this.at, this.length, this.text);
}

class Collector extends RecursiveAstVisitor<void> {
  final String source;
  final changes = <Change>[];
  final constants = <int, Change>{};
  final phrases = <String>{};
  Collector(this.source);
  void collect(StringLiteral node) {
    if (!RegExp('[А-Яа-яЁё]').hasMatch(node.toSource())) return;
    // Only presentation arguments. Keep model data, route values and identifiers intact.
    AstNode? p = node.parent;
    bool ui = false;
    while (p != null) {
      if (p is MethodInvocation &&
          p.target?.toSource() == 'AppLocalizations' &&
          p.methodName.name == 'text')
        return;
      if (p is FieldDeclaration || p is TopLevelVariableDeclaration) return;
      if (p is NamedExpression &&
          const {
            'title',
            'subtitle',
            'label',
            'tooltip',
            'hintText',
            'labelText',
            'helperText',
            'errorText',
            'message',
            'semanticLabel',
          }.contains(p.name.label.name))
        ui = true;
      if (p is ArgumentList) {
        final parent = p.parent;
        final name = switch (parent) {
          InstanceCreationExpression() =>
            parent.constructorName.type.name.lexeme,
          MethodInvocation() => parent.methodName.name,
          _ => '',
        };
        if (!ui &&
            !const {
              'Text',
              'choice',
              'slider',
              '_range',
              '_section',
              '_colorRow',
              '_showGlassMenu',
              'show',
            }.contains(name))
          return;
        if (parent is InstanceCreationExpression &&
            parent.constructorName.type.name.lexeme == 'Text' &&
            p.arguments.isNotEmpty &&
            node.offset >= p.arguments.first.offset &&
            node.end <= p.arguments.first.end)
          ui = true;
        if (parent is MethodInvocation &&
            const {
              'Text',
              'choice',
              'slider',
              '_range',
              '_section',
              '_colorRow',
              '_showGlassMenu',
            }.contains(parent.methodName.name) &&
            p.arguments.isNotEmpty &&
            node.offset >= p.arguments.first.offset &&
            node.end <= p.arguments.first.end)
          ui = true;
        if (parent is MethodInvocation &&
            parent.methodName.name == 'show' &&
            parent.target?.toSource() == 'CustomNotification')
          ui = true;
      }
      p = p.parent;
    }
    if (!ui) return;
    String phrase;
    final expressions = <String>[];
    if (node is SimpleStringLiteral) {
      phrase = node.value;
    } else if (node is StringInterpolation) {
      final b = StringBuffer();
      for (final element in node.elements) {
        if (element is InterpolationString) b.write(element.value);
        if (element is InterpolationExpression) {
          b.write('{${expressions.length}}');
          expressions.add(element.expression.toSource());
        }
      }
      phrase = b.toString();
    } else {
      return;
    }
    phrases.add(phrase);
    final arg = expressions.isEmpty
        ? ''
        : ', args: [${expressions.join(', ')}]';
    changes.add(
      Change(
        node.offset,
        node.length,
        'AppLocalizations.text(context, ${jsonEncode(phrase)}$arg)',
      ),
    );
    p = node.parent;
    while (p != null) {
      final token = switch (p) {
        InstanceCreationExpression() => p.keyword,
        ListLiteral() => p.constKeyword,
        SetOrMapLiteral() => p.constKeyword,
        VariableDeclarationList() => p.keyword,
        _ => null,
      };
      if (token?.lexeme == 'const')
        constants[token!.offset] = Change(
          token.offset,
          token.length,
          p is VariableDeclarationList ? 'final' : '',
        );
      p = p.parent;
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => collect(node);
  @override
  void visitStringInterpolation(StringInterpolation node) => collect(node);
}

void main(List<String> args) {
  final phrases = <String>{};
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.contains('/core/')) continue;
    final source = file.readAsStringSync();
    final c = Collector(source);
    parseString(content: source).unit.accept(c);
    if (c.changes.isEmpty) continue;
    phrases.addAll(c.phrases);
    if (args.contains('--write')) {
      var updated = source;
      final edits = [...c.changes, ...c.constants.values]
        ..sort((a, b) => b.at.compareTo(a.at));
      for (final edit in edits)
        updated = updated.replaceRange(
          edit.at,
          edit.at + edit.length,
          edit.text,
        );
      if (!source.contains("localization/app_localizations.dart'")) {
        final prefix = file.path == 'lib/main.dart'
            ? 'core'
            : file.path.startsWith('lib/shared/widgets/')
            ? '../../core'
            : '../core';
        updated =
            "import '$prefix/localization/app_localizations.dart';\n$updated";
      }
      file.writeAsStringSync(updated);
    }
  }
  File('build/verification/ui-phrases.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(phrases.toList()..sort()),
  );
  print('${phrases.length} UI phrases');
}
