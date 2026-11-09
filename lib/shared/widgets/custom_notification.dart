import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CustomNotification {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static int _generation = 0;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    OverlayState? overlay,
  }) {
    if (!context.mounted) return;
    final accent = Theme.of(context).colorScheme.primary;
    _removeCurrent();
    final generation = ++_generation;
    final overlayState = overlay ?? Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.of(overlayContext).padding.top + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: ValueKey(generation),
            direction: DismissDirection.horizontal,
            onDismissed: (_) {
              if (identical(_currentEntry, entry)) _removeCurrent();
            },
            child: TweenAnimationBuilder<double>(
              duration: 400.ms,
              curve: Curves.easeOutBack,
              tween: Tween(begin: -100.0, end: 0.0),
              builder: (context, value, child) => Transform.translate(
                offset: Offset(0, value),
                child: Opacity(
                  opacity: ((value + 100) / 100).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: isError
                          ? Colors.redAccent.withOpacity(0.2)
                          : const Color(0xFF17171D).withOpacity(0.34),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isError
                            ? Colors.redAccent.withOpacity(0.35)
                            : Colors.white.withOpacity(0.1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isError
                                ? Colors.redAccent.withOpacity(0.2)
                                : accent.withOpacity(0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isError
                                ? Icons.error_outline_rounded
                                : Icons.info_outline_rounded,
                            color: isError ? Colors.redAccent : accent,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (identical(_currentEntry, entry)) _removeCurrent();
    });
  }

  static void _removeCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
