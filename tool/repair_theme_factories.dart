import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Repair extends RecursiveAstVisitor<void> {
  final edits = <({int start, int end, String value})>[];
  void inspect(AstNode node, ArgumentList args) {
    for (final arg in args.arguments.whereType<NamedExpression>()) {
      if (arg.name.label.name != 'child') continue;
      final child = arg.expression;
      if (child is MethodInvocation && child.methodName.name == 'styleFrom')
        edits.add((start: node.offset, end: node.end, value: child.toSource()));
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation n) {
    if (n.target is SimpleIdentifier &&
        (n.target as SimpleIdentifier).name == 'ThemeRegion')
      inspect(n, n.argumentList);
    super.visitMethodInvocation(n);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression n) {
    if (n.constructorName.type.name.lexeme == 'ThemeRegion')
      inspect(n, n.argumentList);
    super.visitInstanceCreationExpression(n);
  }
}

void main() {
  for (final file in [
    File('lib/main.dart'),
    ...Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
  ]) {
    var source = file.readAsStringSync();
    final visitor = Repair();
    parseString(content: source).unit.accept(visitor);
    for (final e in visitor.edits..sort((a, b) => b.start.compareTo(a.start))) {
      source = source.substring(0, e.start) + e.value + source.substring(e.end);
    }
    if (visitor.edits.isNotEmpty) {
      file.writeAsStringSync(source);
      stdout.writeln('${file.path}: ${visitor.edits.length}');
    }
  }
}
