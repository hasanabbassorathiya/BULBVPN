import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_icons.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bulbvpn/core/data/local/vpn_data/vpn_data.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToMain();
  }

  Future<void> _navigateToMain() async {
    final vpnData = await ref.read(vpnDataProvider.future);
    if (vpnData.isVPNEnabled && mounted) {
      context.go('/main');
      return;
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              const Spacer(flex: 10),
              // Logo entrance: settle on a spring.
              StaggeredIn(
                offset: 24,
                child: AppIcons.logo(width: 116, height: 116),
              ),
              const SizedBox(height: 26),
              StaggeredIn(
                delayMs: 140,
                offset: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: const [
                    Text(
                      'BULB',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                    Text(
                      'VPN',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 10),
              StaggeredIn(
                delayMs: 300,
                offset: 8,
                child: Text(
                  'ESTABLISHING LINK',
                  style: AppTextStyles.microLabel(),
                ),
              ),
              const SizedBox(height: 16),
              // Thin indeterminate progress hairline (no spinners — DESIGN.md §7).
              SizedBox(
                width: 132,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: AppColors.graphite,
                    color: AppColors.amber,
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
