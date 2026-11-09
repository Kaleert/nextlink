import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// Run once for new UI source. IDs are written into the source and remain stable
// through formatting and subsequent code edits. ParentData widgets are excluded.
const targets = {
  'Text',
  'Icon',
  'TextField',
  'TextFormField',
  'IconButton',
  'TextButton',
  'FilledButton',
  'OutlinedButton',
  'ElevatedButton',
  'ListTile',
  'SwitchListTile',
  'CheckboxListTile',
  'Switch',
  'Checkbox',
  'Slider',
  'Container',
  'Card',
  'Row',
  'Column',
  'Wrap',
  'Stack',
};

class Patch {
  final int at;
  final String text;
  Patch(this.at, this.text);
}

class Instrument extends RecursiveAstVisitor<void> {
  final String file;
  final List<Patch> patches = [];
  final Map<String, String> catalog;
  int count = 0;
  Instrument(this.file, this.catalog);
  void record(Expression node, String name) {
    if (!targets.contains(name)) return;
    // Do not instrument an already generated wrapper again.
    if (node.parent is NamedExpression &&
        node.parent!.parent?.parent is InstanceCreationExpression) {
      final p = node.parent!.parent!.parent as InstanceCreationExpression;
      if (p.constructorName.type.name.lexeme == 'ThemeRegion') return;
    }
    final id =
        'widget_${file.split('/').last.replaceAll('.dart', '')}_${count++}';
    if (catalog.containsKey(id))
      throw StateError('ID collision; use a new instrumentation prefix');
    final label = '$name · ${file.split('/').last}';
    catalog[id] = label;
    patches.add(
      Patch(
        node.offset,
        'ThemeRegion.auto(id:${jsonEncode(id)}, label:${jsonEncode(label)}, child:',
      ),
    );
    patches.add(Patch(node.end, ')'));
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    record(node, node.constructorName.type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'styleFrom') return;
    final target = node.target;
    final name = target is SimpleIdentifier && targets.contains(target.name)
        ? target.name
        : node.methodName.name;
    record(node, name);
    super.visitMethodInvocation(node);
  }
}

void main(List<String> args) {
  final files = args.isEmpty
      ? [
          File('lib/main.dart'),
          ...Directory('lib/screens').listSync().whereType<File>().where(
            (f) =>
                f.path.endsWith('.dart') &&
                ![
                  'theme_editor_screen.dart',
                  'theme_screen_preview.dart',
                  'theme_live_editor.dart',
                  'qr_import_screen.dart',
                ].contains(f.uri.pathSegments.last),
          ),
        ]
      : args.map(File.new).toList();
  final catalog = <String, String>{};
  for (final file in files) {
    var source = file.readAsStringSync();
    if (source.contains('ThemeRegion.auto(')) {
      stdout.writeln('Skip ${file.path}: already instrumented');
      continue;
    }
    final ast = parseString(content: source, throwIfDiagnostics: false).unit;
    final visitor = Instrument(file.path, catalog);
    ast.accept(visitor);
    final edits = visitor.patches..sort((a, b) => b.at.compareTo(a.at));
    for (final patch in edits) {
      source =
          source.substring(0, patch.at) +
          patch.text +
          source.substring(patch.at);
    }
    if (edits.isNotEmpty &&
        !source.contains("import '../shared/widgets/theme_region.dart';") &&
        !source.contains("import 'shared/widgets/theme_region.dart';")) {
      source =
          "import '${file.path == 'lib/main.dart' ? 'shared' : '../shared'}/widgets/theme_region.dart';\n$source";
    }
    file.writeAsStringSync(source);
    stdout.writeln('${file.path}: ${visitor.count} widgets');
  }
}
