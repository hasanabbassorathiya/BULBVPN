import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/simple_colors.dart';

/// A single-line or expanding text field on the card surface.
class SimpleField extends StatelessWidget {
  const SimpleField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.expands = false,
    this.keyboardType,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool expands;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return TextField(
      controller: controller,
      enabled: enabled,
      expands: expands,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Vazirmatn',
      ),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.white60,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          fontFamily: 'Vazirmatn',
        ),
        filled: true,
        fillColor: s.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: s.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: s.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: s.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
