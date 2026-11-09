import 'package:flutter/material.dart';

class AnsiParser {
  static const String _ansiEscape = '\x1b[';

  static List<TextSpan> parse(String text, {TextStyle? baseStyle}) {
    final List<TextSpan> spans = [];
    int start = 0;
    TextStyle currentStyle = baseStyle ?? const TextStyle();

    while (true) {
      final int escapeIndex = text.indexOf(_ansiEscape, start);
      if (escapeIndex == -1) {
        spans.add(TextSpan(text: text.substring(start), style: currentStyle));
        break;
      }

      if (escapeIndex > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, escapeIndex),
            style: currentStyle,
          ),
        );
      }

      final int endMarkerIndex = text.indexOf('m', escapeIndex);
      if (endMarkerIndex == -1) {
        spans.add(
          TextSpan(text: text.substring(escapeIndex), style: currentStyle),
        );
        break;
      }

      final String code = text.substring(escapeIndex + 2, endMarkerIndex);
      currentStyle = _updateStyle(currentStyle, code, baseStyle);
      start = endMarkerIndex + 1;
    }

    return spans;
  }

  static TextStyle _updateStyle(
    TextStyle current,
    String code,
    TextStyle? baseStyle,
  ) {
    if (code == '0' || code == '') {
      return baseStyle ?? const TextStyle();
    }

    final List<int> parts = code
        .split(';')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    TextStyle next = current;

    int i = 0;
    while (i < parts.length) {
      final int p = parts[i];

      if (p == 0) {
        next = baseStyle ?? const TextStyle();
      } else if (p == 1) {
        next = next.copyWith(fontWeight: FontWeight.bold);
      } else if (p >= 30 && p <= 37) {
        next = next.copyWith(color: _get3BitColor(p - 30));
      } else if (p >= 90 && p <= 97) {
        next = next.copyWith(color: _get3BitColor(p - 90, bright: true));
      } else if (p == 38) {
        // Extended color
        if (i + 2 < parts.length && parts[i + 1] == 5) {
          next = next.copyWith(color: _get256Color(parts[i + 2]));
          i += 2;
        } else if (i + 4 < parts.length && parts[i + 1] == 2) {
          next = next.copyWith(
            color: Color.fromARGB(
              255,
              parts[i + 2],
              parts[i + 3],
              parts[i + 4],
            ),
          );
          i += 4;
        }
      } else if (p == 39) {
        next = next.copyWith(color: baseStyle?.color);
      }
      i++;
    }

    return next;
  }

  static Color _get3BitColor(int index, {bool bright = false}) {
    switch (index) {
      case 0:
        return bright ? Colors.grey : Colors.black;
      case 1:
        return bright ? Colors.redAccent : Colors.red;
      case 2:
        return bright ? Colors.greenAccent : Colors.green;
      case 3:
        return bright ? Colors.yellowAccent : Colors.yellow;
      case 4:
        return bright ? Colors.blueAccent : Colors.blue;
      case 5:
        return bright ? Colors.purpleAccent : Colors.purple;
      case 6:
        return bright ? Colors.cyanAccent : Colors.cyan;
      case 7:
        return bright ? Colors.white : Colors.white70;
      default:
        return Colors.white;
    }
  }

  static Color _get256Color(int index) {
    if (index < 8) return _get3BitColor(index);
    if (index < 16) return _get3BitColor(index - 8, bright: true);
    if (index < 232) {
      // 6x6x6 color cube
      int r = ((index - 16) / 36).floor() * 51;
      int g = (((index - 16) % 36) / 6).floor() * 51;
      int b = ((index - 16) % 6) * 51;
      return Color.fromARGB(255, r, g, b);
    }
    // Grayscale ramp
    int gray = (index - 232) * 10 + 8;
    return Color.fromARGB(255, gray, gray, gray);
  }
}
