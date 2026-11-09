import 'package:flutter/material.dart';

/// Keep actions at the trailing edge; only the title scales on narrow screens.
class AdaptiveHomeHeader extends StatelessWidget {
  final Widget title;
  final Widget actions;
  const AdaptiveHomeHeader({
    super.key,
    required this.title,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: title,
          ),
        ),
      ),
      const SizedBox(width: 12),
      actions,
    ],
  );
}
