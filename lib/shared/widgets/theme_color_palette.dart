import '../../core/localization/app_localizations.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

class ThemeColorPalette extends StatefulWidget {
  final Color initial;
  const ThemeColorPalette({required this.initial});
  @override
  State<ThemeColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<ThemeColorPalette> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: _PaletteGlass(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.text(
                context,
                "Перетащите маркер для выбора цвета",
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                void pick(Offset p) => setState(
                  () => hsv = hsv
                      .withSaturation((p.dx / c.maxWidth).clamp(0, 1))
                      .withValue((1 - p.dy / 160).clamp(0, 1)),
                );
                return GestureDetector(
                  onPanDown: (d) => pick(d.localPosition),
                  onPanUpdate: (d) => pick(d.localPosition),
                  child: SizedBox(
                    height: 160,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: (hsv.saturation * c.maxWidth - 7).clamp(
                            0,
                            c.maxWidth - 14,
                          ),
                          top: ((1 - hsv.value) * 160 - 7).clamp(0, 146),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            for (final channel in ['R', 'G', 'B'])
              Row(
                children: [
                  SizedBox(width: 22, child: Text(channel)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 255,
                      divisions: 255,
                      activeColor: channel == 'R'
                          ? Colors.redAccent
                          : channel == 'G'
                          ? Colors.greenAccent
                          : Colors.blueAccent,
                      value:
                          (channel == 'R'
                              ? hsv.toColor().r
                              : channel == 'G'
                              ? hsv.toColor().g
                              : hsv.toColor().b) *
                          255,
                      onChanged: (v) => setState(() {
                        final c = hsv.toColor();
                        hsv = HSVColor.fromColor(
                          Color.fromARGB(
                            (c.a * 255).round(),
                            channel == 'R' ? v.round() : (c.r * 255).round(),
                            channel == 'G' ? v.round() : (c.g * 255).round(),
                            channel == 'B' ? v.round() : (c.b * 255).round(),
                          ),
                        );
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      ((channel == 'R'
                                  ? hsv.toColor().r
                                  : channel == 'G'
                                  ? hsv.toColor().g
                                  : hsv.toColor().b) *
                              255)
                          .round()
                          .toString(),
                    ),
                  ),
                ],
              ),
            Text(
              '#${hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            ),
            Row(
              children: [
                Expanded(child: Container(height: 28, color: hsv.toColor())),
                TextButton(
                  onPressed: () => Navigator.pop(context, hsv.toColor()),
                  child: Text(AppLocalizations.text(context, "Выбрать")),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PaletteGlass extends StatelessWidget {
  final Widget child;
  const _PaletteGlass({required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .66),
        child: child,
      ),
    ),
  );
}
