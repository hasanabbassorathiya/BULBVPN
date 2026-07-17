import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/analytics_service.dart';
import '../widgets/components/app_button.dart';
import '../widgets/components/app_badge.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isYearly = true;
  bool _isProSelected = false;
  bool _isPremiumSelected = true;
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    AnalyticsService().logSubscriptionViewed(tier: _isPremiumSelected ? 'premium' : 'pro');

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pop(context, false);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.bgDark,
              const Color(0xFF0D1B2A),
              AppColors.bgDark,
            ],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.xl),
                        _buildHeader(colors),
                        const SizedBox(height: AppSpacing.xxl),
                        _buildBillingToggle(colors),
                        const SizedBox(height: AppSpacing.xl),
                        _buildPlanCards(context, colors, isSmallScreen),
                        const SizedBox(height: AppSpacing.xxl),
                        _buildFeatureComparison(colors),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
                _buildBottomLinks(colors),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppSemanticColors colors) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.heroGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.rocket_launch_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Upgrade to Premium',
          style: AppTypography.displayMedium(context).copyWith(
            color: colors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Unlock the full BULB VPN experience',
          style: AppTypography.bodyMedium(context).copyWith(
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBillingToggle(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption('Monthly', !_isYearly, colors, () {
            setState(() => _isYearly = false);
          }),
          _buildToggleOption('Yearly', _isYearly, colors, () {
            setState(() => _isYearly = true);
          }),
        ],
      ),
    );
  }

  Widget _buildToggleOption(String label, bool isActive, AppSemanticColors colors, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.heroGradient : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: AppRadius.pillAll,
          boxShadow: isActive
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.black : colors.textSecondary,
              ),
            ),
            if (label == 'Yearly') ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.black.withValues(alpha: 0.2)
                      : AppColors.success.withValues(alpha: 0.15),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  'Save 50%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.black : AppColors.success,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCards(BuildContext context, AppSemanticColors colors, bool isSmallScreen) {
    return isSmallScreen
        ? Column(
            children: [
              _buildProCard(context, colors),
              const SizedBox(height: AppSpacing.lg),
              _buildPremiumCard(context, colors),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildProCard(context, colors)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildPremiumCard(context, colors)),
            ],
          );
  }

  Widget _buildProCard(BuildContext context, AppSemanticColors colors) {
    final isSelected = _isProSelected;
    final borderColor = isSelected ? AppColors.info : colors.cardBorder;
    final shadow = isSelected
        ? [BoxShadow(color: AppColors.info.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)]
        : <BoxShadow>[];

    final monthly = _isYearly ? '\$2.50/mo' : null;

    return GestureDetector(
      onTap: () => setState(() {
        _isProSelected = true;
        _isPremiumSelected = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppBadge(
                  label: 'Pro',
                  color: AppColors.info,
                  icon: Icons.diamond_outlined,
                  size: AppBadgeSize.medium,
                ),
                const Spacer(),
                if (_isYearly)
                  AppBadge(
                    label: 'Best Value',
                    color: AppColors.success,
                    size: AppBadgeSize.small,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '\$4.99',
              style: AppTypography.displayMedium(context).copyWith(color: colors.textPrimary),
            ),
            Text(
              _isYearly ? '\$29.99/year' : '\$4.99/month',
              style: AppTypography.bodySmall(context),
            ),
            if (monthly != null) ...[
              const SizedBox(height: 2),
              Text(
                monthly,
                style: AppTypography.labelMedium(context).copyWith(color: AppColors.success),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _buildFeatureItem('All servers worldwide', true, colors),
            _buildFeatureItem('Fastest routing', true, colors),
            _buildFeatureItem('Streaming optimized', true, colors),
            _buildFeatureItem('5 devices', true, colors),
            _buildFeatureItem('No ads', true, colors),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Start Pro',
              variant: AppButtonVariant.outlined,
              color: AppColors.info,
              isFullWidth: true,
              onPressed: () => _handlePurchase('pro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumCard(BuildContext context, AppSemanticColors colors) {
    final isSelected = _isPremiumSelected;
    final borderColor = isSelected ? AppColors.primary : colors.cardBorder;
    final shadow = isSelected
        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2)]
        : <BoxShadow>[];

    return GestureDetector(
      onTap: () => setState(() {
        _isPremiumSelected = true;
        _isProSelected = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium, size: 14, color: Colors.black),
                        SizedBox(width: 4),
                        Text(
                          'Premium',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_isYearly)
                  AppBadge(
                    label: 'Most Popular',
                    color: AppColors.warning,
                    size: AppBadgeSize.small,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '\$9.99',
              style: AppTypography.displayMedium(context).copyWith(color: colors.textPrimary),
            ),
            Text(
              _isYearly ? '\$59.99/year' : '\$9.99/month',
              style: AppTypography.bodySmall(context),
            ),
            if (_isYearly) ...[
              const SizedBox(height: 2),
              Text(
                '\$5.00/mo',
                style: AppTypography.labelMedium(context).copyWith(color: AppColors.success),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _buildFeatureItem('Everything in Pro', true, colors),
            _buildFeatureItem('Exclusive servers', true, colors),
            _buildFeatureItem('Priority + fastest speed', true, colors),
            _buildFeatureItem('Streaming optimized', true, colors),
            _buildFeatureItem('Gaming low-latency', true, colors),
            _buildFeatureItem('10 devices', true, colors),
            _buildFeatureItem('24/7 support', true, colors),
            _buildFeatureItem('All protocols', true, colors),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Go Premium',
              variant: AppButtonVariant.filled,
              color: AppColors.primary,
              isFullWidth: true,
              onPressed: () => _handlePurchase('premium'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String label, bool included, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: included ? AppColors.success : AppColors.error.withValues(alpha: 0.5),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall(context).copyWith(
                color: included ? colors.textSecondary : colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureComparison(AppSemanticColors colors) {
    final features = [
      _FeatureRow('Servers', '3 servers', 'All servers', 'All + Exclusive'),
      _FeatureRow('Speed', 'Standard', 'Fastest routing', 'Fastest + Priority'),
      _FeatureRow('Streaming', '✗', '✓', '✓ Optimized'),
      _FeatureRow('Gaming', '✗', '✗', '✓ Low latency'),
      _FeatureRow('Devices', '1', '5', '10'),
      _FeatureRow('Ads', 'Yes', 'No', 'No'),
      _FeatureRow('Support', 'Basic', 'Priority', '24/7'),
      _FeatureRow('Protocol', 'OpenVPN', 'OpenVPN + WireGuard', 'All protocols'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMPARISON',
          style: AppTypography.labelLarge(context).copyWith(
            color: colors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.cardBorder),
          ),
          child: Column(
            children: [
              _buildComparisonHeader(colors),
              ...features.map((f) => _buildComparisonRow(f, colors)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonHeader(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.cardBorder.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('Feature', style: AppTypography.labelMedium(context).copyWith(color: colors.textMuted)),
          ),
          Expanded(child: Center(child: Text('Free', style: AppTypography.labelMedium(context).copyWith(color: colors.textMuted)))),
          Expanded(child: Center(child: Text('Pro', style: AppTypography.labelMedium(context).copyWith(color: AppColors.info)))),
          Expanded(child: Center(child: Text('Premium', style: AppTypography.labelMedium(context).copyWith(color: AppColors.primary)))),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(_FeatureRow feature, AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardBorder.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(feature.name, style: AppTypography.bodySmall(context).copyWith(color: colors.textPrimary)),
          ),
          Expanded(
            child: Center(
              child: _buildComparisonCell(feature.free),
            ),
          ),
          Expanded(
            child: Center(
              child: _buildComparisonCell(feature.pro),
            ),
          ),
          Expanded(
            child: Center(
              child: _buildComparisonCell(feature.premium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCell(String value) {
    final bool isCheck = value.startsWith('✓');
    final bool isCross = value == '✗';

    if (isCross) {
      return const Icon(Icons.close_rounded, size: 16, color: AppColors.error);
    }
    if (isCheck) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 14, color: AppColors.success),
          if (value.length > 1) ...[
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                value.substring(2),
                style: AppTypography.labelSmall(context).copyWith(color: AppColors.success),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    }

    return Text(
      value,
      style: AppTypography.labelSmall(context),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBottomLinks(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          GestureDetector(
            onTap: _handleRestore,
            child: Text(
              _isRestoring ? 'Restoring...' : 'Restore Purchases',
              style: AppTypography.bodyMedium(context).copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {},
                child: Text(
                  'Terms of Service',
                  style: AppTypography.labelSmall(context).copyWith(
                    color: colors.textMuted,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('|', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'Privacy Policy',
                  style: AppTypography.labelSmall(context).copyWith(
                    color: colors.textMuted,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: () => Navigator.pop(context, false),
            child: Text(
              'Continue with Free',
              style: AppTypography.bodyMedium(context).copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchase(String plan) async {
    HapticFeedback.mediumImpact();
    final tier = plan;
    final period = _isYearly ? 'yearly' : 'monthly';
    try {
      await Future.delayed(const Duration(seconds: 2));
      AnalyticsService().logSubscriptionPurchased(tier: tier, period: period);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);

    try {
      await Future.delayed(const Duration(seconds: 2));
      AnalyticsService().logRestorePurchased(success: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No previous purchases found.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      AnalyticsService().logRestorePurchased(success: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }
}

class _FeatureRow {
  final String name;
  final String free;
  final String pro;
  final String premium;

  const _FeatureRow(this.name, this.free, this.pro, this.premium);
}
