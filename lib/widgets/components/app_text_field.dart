import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// A premium text input field with semantic theming and validation support.
///
/// Automatically adapts to dark and light themes via [AppSemanticColors].
/// Supports prefix/suffix icons, obscured text, error states, and custom styling.
///
/// ```dart
/// AppTextField(
///   label: 'Server Address',
///   hint: 'e.g. vpn.example.com',
///   prefixIcon: Icons.dns_outlined,
///   validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
/// )
/// ```
class AppTextField extends StatelessWidget {
  /// Label text displayed above the field.
  final String? label;

  /// Placeholder text when the field is empty.
  final String? hint;

  /// Current field value.
  final String? value;

  /// Callback when the field value changes.
  final ValueChanged<String>? onChanged;

  /// Form validator for use within a [Form].
  final FormFieldValidator<String>? validator;

  /// Whether the text should be obscured (e.g. passwords).
  final bool obscureText;

  /// Optional prefix icon.
  final IconData? prefixIcon;

  /// Optional suffix icon or widget (e.g. clear button).
  final Widget? suffixIcon;

  /// Keyboard type hint for the input.
  final TextInputType keyboardType;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Tap callback when the field is read-only or for custom tap handling.
  final VoidCallback? onTap;

  /// Maximum number of lines. Defaults to 1 (single line).
  final int maxLines;

  /// Text editing controller for programmatic control.
  final TextEditingController? controller;

  /// Focus node for focus management.
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.value,
    this.onChanged,
    this.validator,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.controller,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.labelLarge(context).copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          initialValue: value,
          onChanged: onChanged,
          validator: validator,
          obscureText: obscureText,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: maxLines,
          style: AppTypography.bodyLarge(context).copyWith(
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodyMedium(context).copyWith(
              color: colors.textMuted,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 20, color: colors.textMuted)
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: colors.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.lgAll,
              borderSide: BorderSide(color: colors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgAll,
              borderSide: BorderSide(color: colors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgAll,
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgAll,
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgAll,
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
            errorStyle: AppTypography.labelSmall(context).copyWith(
              color: AppColors.error,
            ),
          ),
        ),
      ],
    );
  }
}
