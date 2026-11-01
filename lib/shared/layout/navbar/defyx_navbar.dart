import 'package:bulbvpn/app/router/app_router.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The bottom bar: three destinations on the rail, then 44 px actions.
/// A single hairline separates it from the field; there is no floating pill.
class DefyxNavBar extends StatelessWidget {
  const DefyxNavBar({super.key});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final path = GoRouterState.of(context).uri.path;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: air.surface,
        border: Border(top: BorderSide(color: air.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: _NavDestination(
                  icon: Icons.horizontal_rule,
                  label: 'Connect',
                  active: path == DefyxVPNRoutes.main.route,
                  onTap: () => context.go(DefyxVPNRoutes.main.route),
                ),
              ),
              Expanded(
                child: _NavDestination(
                  icon: Icons.public,
                  label: 'Servers',
                  active: false,
                  onTap: () => _openServers(context),
                ),
              ),
              Expanded(
                child: _NavDestination(
                  icon: Icons.speed,
                  label: 'Speed',
                  active: path == DefyxVPNRoutes.speedTest.route,
                  onTap: () => context.go(DefyxVPNRoutes.speedTest.route),
                ),
              ),
              _NavAction(
                icon: Icons.tune,
                tooltip: 'Settings',
                onTap: () => context.go(DefyxVPNRoutes.settings.route),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openServers(BuildContext context) async {
    // Leaving the sheet's owner route mid-audit is not offered: jump to the
    // connect surface first, then open on the next frame.
    if (GoRouterState.of(context).uri.path != DefyxVPNRoutes.main.route) {
      context.go(DefyxVPNRoutes.main.route);
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
    }
    await showServerSheet(context);
  }
}

class _NavDestination extends StatelessWidget {
  const _NavDestination({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final color = active ? air.ink : air.steel;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 2,
              width: active ? 18 : 0,
              color: air.accent,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label(
                color: color,
                size: 11,
                tracking: 0.4,
              ).copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavAction extends StatelessWidget {
  const _NavAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: context.air.steel),
      ),
    );
  }
}
