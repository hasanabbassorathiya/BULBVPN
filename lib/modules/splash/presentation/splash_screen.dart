import 'package:bulbvpn/core/data/local/vpn_data/vpn_data.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/legal/legal_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _line.forward();
    _navigateToMain();
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _navigateToMain() async {
    final vpnData = await ref.read(vpnDataProvider.future);
    final accepted = await LegalAcceptance.isAccepted();
    if (!accepted && mounted) {
      context.go('/legal');
      return;
    }
    if (vpnData.isVPNEnabled && mounted) {
      context.go('/main');
      return;
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: air.ground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'BULB',
                    style: AppTextStyles.display(
                      color: air.ink,
                      size: 26,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'VPN',
                    style: AppTextStyles.display(
                      color: air.accentInk,
                      size: 26,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // One rule draws itself; that is the whole animation.
              AnimatedBuilder(
                animation: _line,
                builder: (context, _) => Container(
                  width: reduced ? 120 : 48 + 72 * _line.value,
                  height: 1,
                  color: air.hairlineStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
