import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../models/in_app_message.dart';

class PromoBanner extends StatefulWidget {
  final InAppMessage message;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const PromoBanner({
    super.key,
    required this.message,
    this.onAction,
    this.onDismiss,
  });

  @override
  State<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<PromoBanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final msg = widget.message;

    Color bgColor;
    IconData icon;

    switch (msg.type) {
      case InAppMessageType.promotional:
        bgColor = AppColors.accent.withValues(alpha: 0.15);
        icon = Icons.local_offer;
      case InAppMessageType.upgrade:
        bgColor = AppColors.primary.withValues(alpha: 0.15);
        icon = Icons.upgrade;
      case InAppMessageType.feature:
        bgColor = AppColors.info.withValues(alpha: 0.15);
        icon = Icons.info_outline;
      case InAppMessageType.announcement:
        bgColor = AppColors.warning.withValues(alpha: 0.15);
        icon = Icons.campaign;
      case InAppMessageType.survey:
        bgColor = AppColors.secondary.withValues(alpha: 0.15);
        icon = Icons.poll;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.textPrimary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      msg.body,
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (msg.actionText != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      msg.actionText!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.bgDark,
                      ),
                    ),
                  ),
                ),
              ],
              if (msg.dismissible) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _controller.reverse().then((_) => widget.onDismiss?.call());
                  },
                  child: Icon(Icons.close, color: colors.textMuted, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
