import '../../core/theme/theme_surface_style.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

/// Compact dropdown that opens as a translucent, blurred option sheet.
class GlassDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color surfaceColor;
  final Color accentColor;
  final Color textColor;
  final Widget? icon;

  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.surfaceColor,
    required this.accentColor,
    this.textColor = Colors.white,
    this.icon,
  });

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX:
                Theme.of(context).extension<ThemeSurfaceStyle>()?.blur ?? 26,
            sigmaY:
                Theme.of(context).extension<ThemeSurfaceStyle>()?.blur ?? 26,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.55,
            ),
            decoration: BoxDecoration(
              color: surfaceColor.withOpacity(
                Theme.of(context).extension<ThemeSurfaceStyle>()?.opacity ??
                    .52,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final isSelected = item.value == value;
                  return Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: item.enabled
                            ? () => Navigator.pop(sheetContext, item.value)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: DefaultTextStyle.merge(
                                  style: TextStyle(
                                    color: isSelected ? accentColor : textColor,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  child: item.child,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_rounded,
                                  color: accentColor,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (item != items.last)
                        Divider(
                          height: 1,
                          indent: 14,
                          endIndent: 14,
                          color: Colors.white.withOpacity(0.06),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = items.cast<DropdownMenuItem<T>?>().firstWhere(
      (item) => item?.value == value,
      orElse: () => null,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: textColor, fontSize: 14),
                child: selectedItem?.child ?? const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 4),
            icon ?? Icon(Icons.arrow_drop_down_rounded, color: accentColor),
          ],
        ),
      ),
    );
  }
}
