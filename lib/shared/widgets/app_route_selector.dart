import 'package:flutter/material.dart';

/// One clipped surface: route buttons share straight inner edges.
class AppRouteSelector extends StatelessWidget {
  final String value;
  final bool supportsBlock, enabled;
  final Color proxyColor;
  final ValueChanged<String> onChanged;

  const AppRouteSelector({
    super.key,
    required this.value,
    this.supportsBlock = false,
    this.enabled = true,
    required this.proxyColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white10),
      ),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            _segment(
              'Proxy',
              'proxy',
              proxyColor,
              const BorderRadius.horizontal(left: Radius.circular(12)),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Colors.white10,
            ),
            _segment(
              'Direct',
              'direct',
              Colors.orangeAccent,
              supportsBlock
                  ? BorderRadius.zero
                  : const BorderRadius.horizontal(right: Radius.circular(12)),
            ),
            if (supportsBlock) ...[
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.white10,
              ),
              _segment(
                'Block',
                'block',
                Colors.redAccent,
                const BorderRadius.horizontal(right: Radius.circular(12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, String mode, Color color, BorderRadius radius) {
    final selected = value == mode;
    return Expanded(
      child: Ink(
        color: selected ? color.withValues(alpha: .2) : Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? () => onChanged(mode) : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
