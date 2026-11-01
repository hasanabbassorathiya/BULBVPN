import 'dart:async';

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/aperture_control.dart';
import 'package:bulbvpn/shared/air/horizon_field.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First-run tour after the clickwrap: what the app does, why relays differ,
/// and what the one permission actually grants. No screenshots, no dots.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _frames = <_OnboardingFrame>[
    _OnboardingFrame(
      title: 'Your path, prepared.',
      body:
          'BULBVPN measures working relays before you tap, so the first byte '
          'arrives sooner.',
      action: 'Continue',
    ),
    _OnboardingFrame(
      title: 'Every network is different.',
      body:
          'Relays that work on one carrier fail on another. The app remembers '
          'per network and switches when the path changes.',
      action: 'Continue',
    ),
    _OnboardingFrame(
      title: 'One permission.',
      body:
          'The VPN permission lets BULBVPN carry your traffic. It cannot see '
          'your screen, messages, or files.',
      action: 'Allow VPN',
      secondary: 'Not now',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _frames.length - 1) {
      _allowVpn();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.fastOutSlowIn,
    );
  }

  /// Starts the existing connect path so the OS permission sheet is the first
  /// thing the user answers, then lands on the connect surface.
  void _allowVpn() {
    final status = ref.read(connectionStateProvider).status;
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet) {
      unawaited(VpnController().handleConnectionButton());
    }
    context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Scaffold(
      backgroundColor: air.ground,
      body: HorizonField(
        phase: AirPhase.idle,
        horizonFraction: 0.44,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Progress(
                fraction: (_index + 1) / _frames.length,
                color: air.accent,
                track: air.hairline,
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _frames.length,
                  onPageChanged: (page) => setState(() => _index = page),
                  itemBuilder: (context, page) {
                    final frame = _frames[page];
                    final last = page == _frames.length - 1;
                    return _Frame(
                      frame: frame,
                      onPrimary: last ? _allowVpn : _next,
                      onSecondary: last
                          ? () => context.go('/main')
                          : null,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Text(
                  'Bootstrap relays are not private. You can import your own '
                  'server later.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label(
                    color: air.steel,
                    size: 11,
                    tracking: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingFrame {
  final String title;
  final String body;
  final String action;
  final String? secondary;

  const _OnboardingFrame({
    required this.title,
    required this.body,
    required this.action,
    this.secondary,
  });
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.frame,
    required this.onPrimary,
    this.onSecondary,
  });

  final _OnboardingFrame frame;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final secondary = onSecondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: ApertureControl(
                        phase: AirPhase.idle,
                        onTap: () {},
                        size: 64,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    frame.title,
                    style: AppTextStyles.display(
                      color: air.ink,
                      size: 30,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      frame.body,
                      style: AppTextStyles.body(
                        color: air.steel,
                        size: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AirButton.primary(
                          label: frame.action,
                          onPressed: onPrimary,
                        ),
                        if (secondary != null) ...[
                          const SizedBox(height: 8),
                          AirButton.secondary(
                            label: frame.secondary!,
                            onPressed: onSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, value, _) => SizedBox(
        height: 1,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
