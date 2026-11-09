import 'dart:ui';

import 'package:flutter/material.dart';

class GlassInputDialog extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String saveLabel;
  final String cancelLabel;
  final Color surfaceColor;
  final Color accentColor;
  final Color textDimColor;
  final String? hintText;
  final String? helperText;
  final TextInputType keyboardType;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const GlassInputDialog({
    super.key,
    required this.title,
    required this.controller,
    required this.saveLabel,
    required this.cancelLabel,
    required this.surfaceColor,
    required this.accentColor,
    required this.textDimColor,
    required this.onCancel,
    required this.onSave,
    this.hintText,
    this.helperText,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.07),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.07),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: accentColor.withOpacity(0.65),
                      ),
                    ),
                  ),
                ),
                if (helperText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    helperText!,
                    style: TextStyle(color: textDimColor, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: Text(
                        cancelLabel,
                        style: TextStyle(color: textDimColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor.withOpacity(0.16),
                        foregroundColor: accentColor,
                        overlayColor: accentColor.withOpacity(0.12),
                      ),
                      child: Text(
                        saveLabel,
                        style: TextStyle(color: accentColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
