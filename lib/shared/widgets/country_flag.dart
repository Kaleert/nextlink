import 'package:flutter/material.dart';

import '../../core/utils/country_flag_assets.dart';

/// Bundled PNGs: no font dependency and no extra requests for flag images.
class CountryFlagImage extends StatelessWidget {
  final String countryCode;
  final double height;
  const CountryFlagImage({
    super.key,
    required this.countryCode,
    this.height = 18,
  });
  @override
  Widget build(BuildContext context) {
    final path = CountryFlagAssets.path(countryCode);
    final fallback = Icon(
      Icons.flag_outlined,
      size: height,
      color: Colors.white54,
    );
    return Semantics(
      label: countryCode.toUpperCase(),
      image: true,
      child: SizedBox(
        width: height * 4 / 3,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: path == null
              ? fallback
              : Image.asset(
                  path,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

/// Render existing flag characters as images, leaving stored names unchanged.
class FlagText extends StatelessWidget {
  final Text original;
  final Color? color;
  const FlagText({super.key, required this.original, this.color});
  static final _flags = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
  static bool containsFlags(String? value) =>
      value != null && _flags.hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final data = original.data;
    if (data == null || !containsFlags(data)) return original;
    final fontSize =
        original.style?.fontSize ??
        DefaultTextStyle.of(context).style.fontSize ??
        14;
    final scaler =
        original.textScaler ??
        (original.textScaleFactor != null
            ? TextScaler.linear(original.textScaleFactor!)
            : MediaQuery.textScalerOf(context));
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in _flags.allMatches(data)) {
      if (match.start > offset)
        spans.add(TextSpan(text: data.substring(offset, match.start)));
      final code = String.fromCharCodes(
        match[0]!.runes.map((r) => r - 0x1f1a5),
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CountryFlagImage(
            countryCode: code,
            height: scaler.scale(fontSize) * .82,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < data.length) spans.add(TextSpan(text: data.substring(offset)));
    return Text.rich(
      TextSpan(children: spans),
      style: color == null
          ? original.style
          : (original.style ?? const TextStyle()).copyWith(color: color),
      strutStyle: original.strutStyle,
      textAlign: original.textAlign,
      textDirection: original.textDirection,
      locale: original.locale,
      softWrap: original.softWrap,
      overflow: original.overflow,
      textScaler: original.textScaler,
      textScaleFactor: original.textScaleFactor,
      maxLines: original.maxLines,
      semanticsLabel: original.semanticsLabel ?? data,
      textWidthBasis: original.textWidthBasis,
      textHeightBehavior: original.textHeightBehavior,
      selectionColor: original.selectionColor,
    );
  }
}
