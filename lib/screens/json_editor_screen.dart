import '../shared/widgets/theme_region.dart';
// lib/screens/json_editor_screen.dart

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../shared/widgets/custom_notification.dart';

class JsonSyntaxController extends TextEditingController {
  int? errorOffset;
  String searchQuery = '';
  int currentMatchIndex = 0;
  List<int> matchOffsets = [];

  JsonSyntaxController({super.text});

  // Выносим обновление офсетов из buildTextSpan для оптимизации
  void updateSearchMatches(String query) {
    searchQuery = query;
    matchOffsets.clear();
    if (searchQuery.isEmpty) {
      currentMatchIndex = 0;
      notifyListeners();
      return;
    }

    final matches = RegExp(
      RegExp.escape(searchQuery),
      caseSensitive: false,
    ).allMatches(text);
    for (final m in matches) {
      matchOffsets.add(m.start);
    }

    if (matchOffsets.isNotEmpty && currentMatchIndex >= matchOffsets.length) {
      currentMatchIndex = 0;
    }
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(style: style, text: '');

    final List<TextSpan> children = [];
    final RegExp syntaxExp = RegExp(
      r'(".*?\"\s*:)|(".*?")|(\b\d+\b)|(\b(true|false|null)\b)|([\{\}\[\]\,\:])',
    );

    int lastEnd = 0;

    // Определяем индекс строки для текущего совпадения, чтобы подсветить всю строку
    int currentMatchLineIndex = -1;
    if (searchQuery.isNotEmpty && matchOffsets.isNotEmpty) {
      final currentOffset = matchOffsets[currentMatchIndex];
      currentMatchLineIndex = '\n'
          .allMatches(text.substring(0, currentOffset))
          .length;
    }

    text.splitMapJoin(
      syntaxExp,
      onMatch: (m) {
        String match = m.group(0)!;
        TextStyle ts = style ?? const TextStyle();

        if (match.endsWith(':')) {
          ts = ts.copyWith(color: Colors.purpleAccent.shade100);
        } else if (match.startsWith('"')) {
          ts = ts.copyWith(color: Colors.greenAccent.shade200);
        } else if (int.tryParse(match) != null ||
            double.tryParse(match) != null) {
          ts = ts.copyWith(color: Colors.orangeAccent);
        } else if (match == 'true' || match == 'false' || match == 'null') {
          ts = ts.copyWith(color: Colors.blueAccent.shade200);
        } else {
          ts = ts.copyWith(color: Colors.white60);
        }

        _processTextPart(match, ts, lastEnd, children, currentMatchLineIndex);
        lastEnd += match.length;
        return '';
      },
      onNonMatch: (n) {
        _processTextPart(n, style, lastEnd, children, currentMatchLineIndex);
        lastEnd += n.length;
        return '';
      },
    );

    return TextSpan(style: style, children: children);
  }

  void _processTextPart(
    String partText,
    TextStyle? baseStyle,
    int startOffset,
    List<TextSpan> children,
    int activeLineIndex,
  ) {
    if (partText.isEmpty) return;

    int localOffset = 0;

    while (localOffset < partText.length) {
      int globalOffset = startOffset + localOffset;

      int currentLine = '\n'.allMatches(text.substring(0, globalOffset)).length;
      bool isLineHighlighted =
          (activeLineIndex != -1 && currentLine == activeLineIndex);

      TextStyle effectiveStyle = (baseStyle ?? const TextStyle());
      if (isLineHighlighted) {
        effectiveStyle = effectiveStyle.copyWith(
          backgroundColor: Colors.white.withOpacity(0.05),
        );
      }

      if (errorOffset != null && globalOffset == errorOffset) {
        children.add(
          TextSpan(
            text: partText.substring(localOffset, localOffset + 1),
            style: effectiveStyle.copyWith(
              backgroundColor: Colors.redAccent.withOpacity(0.4),
              decoration: TextDecoration.underline,
              decorationColor: Colors.redAccent,
              decorationStyle: TextDecorationStyle.wavy,
            ),
          ),
        );
        localOffset++;
        continue;
      }
      
      bool foundSearchMatch = false;
      if (searchQuery.isNotEmpty) {
        for (int i = 0; i < matchOffsets.length; i++) {
          int mStart = matchOffsets[i];
          int mEnd = mStart + searchQuery.length;

          if (globalOffset >= mStart && globalOffset < mEnd) {
            int len = mEnd - globalOffset;
            if (localOffset + len > partText.length)
              len = partText.length - localOffset;

            bool isCurrent = (i == currentMatchIndex);

            children.add(
              TextSpan(
                text: partText.substring(localOffset, localOffset + len),
                style: effectiveStyle.copyWith(
                  backgroundColor: isCurrent
                      ? Colors.orangeAccent.withOpacity(0.8)
                      : Colors.yellowAccent.withOpacity(0.25),
                  color: isCurrent ? Colors.black : null,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                ),
              ),
            );
            localOffset += len;
            foundSearchMatch = true;
            break;
          }
        }
      }

      if (foundSearchMatch) continue;

      // 3. Обычный текст (с учетом подсветки строки)
      children.add(
        TextSpan(text: partText[localOffset], style: effectiveStyle),
      );
      localOffset++;
    }
  }
}

class JsonEditorScreen extends ConsumerStatefulWidget {
  final String initialJson;
  final String serverName;

  const JsonEditorScreen({
    super.key,
    required this.initialJson,
    required this.serverName,
  });

  @override
  ConsumerState<JsonEditorScreen> createState() => _JsonEditorScreenState();
}

class _JsonEditorScreenState extends ConsumerState<JsonEditorScreen> {
  late JsonSyntaxController _controller;
  String? _jsonError;
  bool _isSearchVisible = false;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _lineNumbersCtrl = ScrollController();

  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    String formatted = widget.initialJson;
    try {
      formatted = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(widget.initialJson));
    } catch (_) {}

    _controller = JsonSyntaxController(text: formatted);
    _lineCount = '\n'.allMatches(formatted).length + 1;

    _scrollCtrl.addListener(() {
      if (_lineNumbersCtrl.hasClients) {
        _lineNumbersCtrl.jumpTo(_scrollCtrl.offset);
      }
    });

    _controller.addListener(() {
      final newCount = '\n'.allMatches(_controller.text).length + 1;
      if (newCount != _lineCount) {
        setState(() => _lineCount = newCount);
      }
    });
  }

  void _onSearchChanged(String val) {
    _controller.updateSearchMatches(val);
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _lineNumbersCtrl.dispose();
    super.dispose();
  }

  void _validateJson(String text) {
    if (text.isEmpty) {
      setState(() {
        _jsonError = null;
        _controller.errorOffset = null;
      });
      return;
    }
    try {
      jsonDecode(text);
      setState(() {
        _jsonError = null;
        _controller.errorOffset = null;
      });
    } catch (e) {
      String msg = e.toString().replaceFirst('FormatException: ', '');
      int? offset;
      final match = RegExp(r'\(at character (\d+)\)').firstMatch(msg);
      if (match != null) {
        offset = int.tryParse(match.group(1)!)! - 1;
      }

      setState(() {
        _jsonError = msg;
        _controller.errorOffset = offset;
      });
    }
  }

  void _scrollToCurrentMatch() {
    if (_controller.matchOffsets.isEmpty) return;
    final offset = _controller.matchOffsets[_controller.currentMatchIndex];

    final textBefore = _controller.text.substring(0, offset);
    final lineIndex = '\n'.allMatches(textBefore).length;

    // Каждая строка ~18px (fontSize 12 * height 1.5)
    const lineHeight = 18.0;
    final scrollOffset = lineIndex * lineHeight;

    // Пытаемся центрировать строку
    final viewportHeight = _scrollCtrl.position.viewportDimension;
    final centeredOffset =
        scrollOffset - (viewportHeight / 2) + (lineHeight / 2);

    _scrollCtrl.animateTo(
      centeredOffset.clamp(0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_json_editor',
        child: SafeArea(
          child: ThemeRegion.auto(
            id: "widget_json_editor_screen_0",
            label: "Column · json_editor_screen.dart",
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: ThemeRegion.auto(
                    id: "widget_json_editor_screen_1",
                    label: "Row · json_editor_screen.dart",
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                          },
                          child: ThemeRegion.auto(
                            id: "widget_json_editor_screen_2",
                            label: "Container · json_editor_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.surface.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_json_editor_screen_3",
                                label: "Icon · json_editor_screen.dart",
                                child: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: theme.text,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ThemeRegion.auto(
                            id: "widget_json_editor_screen_4",
                            label: "Text · json_editor_screen.dart",
                            child: Text(
                              '${widget.serverName} [${loc.translate('raw_json_tag')}]',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // Кнопка поиска
                        GestureDetector(
                          onTap: () => setState(
                            () => _isSearchVisible = !_isSearchVisible,
                          ),
                          child: ThemeRegion.auto(
                            id: "widget_json_editor_screen_5",
                            label: "Container · json_editor_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isSearchVisible
                                    ? theme.primary.withOpacity(0.2)
                                    : theme.surface.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _isSearchVisible
                                      ? theme.primary.withOpacity(0.5)
                                      : Colors.white10,
                                ),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_json_editor_screen_6",
                                label: "Icon · json_editor_screen.dart",
                                child: Icon(
                                  Icons.search_rounded,
                                  color: _isSearchVisible
                                      ? theme.primary
                                      : theme.text,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            if (_jsonError == null) {
                              Navigator.pop(context, _controller.text);
                            } else {
                              CustomNotification.show(
                                context,
                                loc.translate('fix_json_errors'),
                                isError: true,
                              );
                            }
                          },
                          child: ThemeRegion.auto(
                            id: "widget_json_editor_screen_7",
                            label: "Container · json_editor_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _jsonError == null
                                    ? theme.primary.withOpacity(0.2)
                                    : Colors.redAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _jsonError == null
                                      ? theme.primary.withOpacity(0.5)
                                      : Colors.redAccent.withOpacity(0.5),
                                ),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_json_editor_screen_8",
                                label: "Icon · json_editor_screen.dart",
                                child: Icon(
                                  Icons.save_rounded,
                                  color: _jsonError == null
                                      ? theme.primary
                                      : Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Search Bar (Redesigned)
                if (_isSearchVisible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: ThemeRegion.auto(
                          id: "widget_json_editor_screen_9",
                          label: "Container · json_editor_screen.dart",
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_json_editor_screen_10",
                              label: "Row · json_editor_screen.dart",
                              child: Row(
                                children: [
                                  ThemeRegion.auto(
                                    id: "widget_json_editor_screen_11",
                                    label: "Icon · json_editor_screen.dart",
                                    child: const Icon(
                                      Icons.search_rounded,
                                      size: 20,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ThemeRegion.auto(
                                      id: "widget_json_editor_screen_12",
                                      label:
                                          "TextField · json_editor_screen.dart",
                                      child: TextField(
                                        controller: _searchCtrl,
                                        autofocus: true,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: loc.translate('search'),
                                          hintStyle: const TextStyle(
                                            color: Colors.white24,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                        onChanged: _onSearchChanged,
                                      ),
                                    ),
                                  ),
                                  if (_controller.searchQuery.isNotEmpty) ...[
                                    ThemeRegion.auto(
                                      id: "widget_json_editor_screen_13",
                                      label: "Text · json_editor_screen.dart",
                                      child: Text(
                                        '${_controller.matchOffsets.isEmpty ? 0 : _controller.currentMatchIndex + 1} / ${_controller.matchOffsets.length}',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: () {
                                        if (_controller.matchOffsets.isEmpty)
                                          return;
                                        setState(() {
                                          _controller.currentMatchIndex =
                                              (_controller.currentMatchIndex -
                                                  1 +
                                                  _controller
                                                      .matchOffsets
                                                      .length) %
                                              _controller.matchOffsets.length;
                                        });
                                        _scrollToCurrentMatch();
                                      },
                                      child: ThemeRegion.auto(
                                        id: "widget_json_editor_screen_14",
                                        label: "Icon · json_editor_screen.dart",
                                        child: const Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        if (_controller.matchOffsets.isEmpty)
                                          return;
                                        setState(() {
                                          _controller.currentMatchIndex =
                                              (_controller.currentMatchIndex +
                                                  1) %
                                              _controller.matchOffsets.length;
                                        });
                                        _scrollToCurrentMatch();
                                      },
                                      child: ThemeRegion.auto(
                                        id: "widget_json_editor_screen_15",
                                        label: "Icon · json_editor_screen.dart",
                                        child: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        _onSearchChanged('');
                                      },
                                      child: ThemeRegion.auto(
                                        id: "widget_json_editor_screen_16",
                                        label: "Icon · json_editor_screen.dart",
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 20,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).animate().fade().slideY(begin: -0.1),

                // Error Banner
                if (_jsonError != null)
                  ThemeRegion.auto(
                    id: "widget_json_editor_screen_17",
                    label: "Container · json_editor_screen.dart",
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.2),
                        ),
                      ),
                      child: ThemeRegion.auto(
                        id: "widget_json_editor_screen_18",
                        label: "Row · json_editor_screen.dart",
                        child: Row(
                          children: [
                            ThemeRegion.auto(
                              id: "widget_json_editor_screen_19",
                              label: "Icon · json_editor_screen.dart",
                              child: const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ThemeRegion.auto(
                                id: "widget_json_editor_screen_20",
                                label: "Text · json_editor_screen.dart",
                                child: Text(
                                  _jsonError!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fade(),

                // Editor
                Expanded(
                  child: ThemeRegion.auto(
                    id: "widget_json_editor_screen_21",
                    label: "Container · json_editor_screen.dart",
                    child: Container(
                      color: const Color(0xFF050505),
                      child: ThemeRegion.auto(
                        id: "widget_json_editor_screen_22",
                        label: "Row · json_editor_screen.dart",
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Номера строк
                            ThemeRegion.auto(
                              id: "widget_json_editor_screen_23",
                              label: "Container · json_editor_screen.dart",
                              child: Container(
                                width: 45,
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  right: 8,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: Colors.white10),
                                  ),
                                  color: Color(0xFF080808),
                                ),
                                child: ListView.builder(
                                  controller: _lineNumbersCtrl,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _lineCount,
                                  itemBuilder: (context, i) => ThemeRegion.auto(
                                    id: "widget_json_editor_screen_24",
                                    label: "Text · json_editor_screen.dart",
                                    child: Text(
                                      '${i + 1}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.2),
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Само поле ввода
                            Expanded(
                              child: ThemeRegion.auto(
                                id: "widget_json_editor_screen_25",
                                label: "TextField · json_editor_screen.dart",
                                child: TextField(
                                  controller: _controller,
                                  scrollController: _scrollCtrl,
                                  maxLines: null,
                                  expands: true,
                                  onChanged: _validateJson,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.5,
                                    fontFamilyFallback: [
                                      'Courier New',
                                      'monospace',
                                    ],
                                  ),
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.all(16),
                                    border: InputBorder.none,
                                    hintText: '{ "protocol": "..." }',
                                    hintStyle: TextStyle(color: Colors.white10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
