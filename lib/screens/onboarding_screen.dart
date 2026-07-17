import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';
import '../widgets/components/app_button.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  const OnboardingScreen({super.key, this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.shield_rounded,
      iconGradient: AppColors.heroGradient,
      title: 'Protect Your Privacy',
      subtitle:
          'BULB VPN encrypts your internet connection and hides your real IP address from trackers, hackers, and ISPs.',
      illustration: _ShieldIllustration(),
    ),
    _OnboardingPage(
      icon: Icons.wifi_rounded,
      iconGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
      ),
      title: 'Stay Safe on Public WiFi',
      subtitle:
          'Public WiFi networks are hunting grounds for hackers. BULB VPN creates a secure tunnel that protects your data on any network.',
      illustration: _WiFiLockIllustration(),
    ),
    _OnboardingPage(
      icon: Icons.speed_rounded,
      iconGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.accent],
      ),
      title: 'Stream Without Limits',
      subtitle:
          'Access content from around the world with optimized servers. No buffering, no throttling, just pure speed.',
      illustration: _GlobeIllustration(),
    ),
    _OnboardingPage(
      icon: Icons.check_circle_rounded,
      iconGradient: AppColors.connectedGradient,
      title: "You're Ready",
      subtitle:
          'One tap is all it takes. Connect to a secure server instantly and browse with confidence.',
      illustration: _ConnectedIllustration(),
    ),
  ];

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _onGetStarted() async {
    await StorageService().setOnboardingComplete(true);
    AnalyticsService().logScreenView(screenName: 'onboarding_completed');
    if (!mounted) return;
    widget.onComplete?.call();
  }

  void _onSkip() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return _AnimatedPageContent(
                  key: ValueKey(index),
                  page: page,
                  colors: colors,
                );
              },
            ),
            if (!isLast)
              Positioned(
                top: 8,
                right: 16,
                child: TextButton(
                  onPressed: _onSkip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomControls(
                isLast: isLast,
                currentPage: _currentPage,
                pageCount: _pages.length,
                onNext: _onNext,
                onGetStarted: _onGetStarted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated Page Content ────────────────────────────────────────────────────
class _AnimatedPageContent extends StatelessWidget {
  final _OnboardingPage page;
  final AppSemanticColors colors;

  const _AnimatedPageContent({
    super.key,
    required this.page,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Icon with gradient circle
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: page.iconGradient,
              boxShadow: [
                BoxShadow(
                  color: page.iconGradient.colors.first.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(page.icon, size: 52, color: Colors.white),
          ),
          const SizedBox(height: 48),
          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Subtitle
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(flex: 2),
          // Illustration
          SizedBox(
            height: 160,
            child: page.illustration,
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

// ─── Bottom Controls ──────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  final bool isLast;
  final int currentPage;
  final int pageCount;
  final VoidCallback onNext;
  final VoidCallback onGetStarted;

  const _BottomControls({
    required this.isLast,
    required this.currentPage,
    required this.pageCount,
    required this.onNext,
    required this.onGetStarted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              final active = i == currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: active ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
          // Button
          isLast
              ? AppButton(
                  label: 'Get Started',
                  icon: Icons.arrow_forward_rounded,
                  isFullWidth: true,
                  onPressed: onGetStarted,
                )
              : AppButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  isFullWidth: true,
                  onPressed: onNext,
                ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Page Data ────────────────────────────────────────────────────────────────
class _OnboardingPage {
  final IconData icon;
  final LinearGradient iconGradient;
  final String title;
  final String subtitle;
  final Widget illustration;

  const _OnboardingPage({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    required this.illustration,
  });
}

// ─── Illustrations ────────────────────────────────────────────────────────────

class _ShieldIllustration extends StatelessWidget {
  const _ShieldIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(160, 160),
      painter: _ShieldPainter(),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Outer glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 70));
    canvas.drawCircle(Offset(cx, cy), 70, glowPaint);

    // Shield path
    final shieldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.primary.withValues(alpha: 0.6);

    final path = Path()
      ..moveTo(cx, cy - 40)
      ..lineTo(cx + 32, cy - 24)
      ..lineTo(cx + 28, cy + 16)
      ..quadraticBezierTo(cx, cy + 44, cx, cy + 44)
      ..quadraticBezierTo(cx, cy + 44, cx - 28, cy + 16)
      ..lineTo(cx - 32, cy - 24)
      ..close();
    canvas.drawPath(path, shieldPaint);

    // Checkmark
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary;

    final check = Path()
      ..moveTo(cx - 12, cy + 2)
      ..lineTo(cx - 2, cy + 14)
      ..lineTo(cx + 14, cy - 12);
    canvas.drawPath(check, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WiFiLockIllustration extends StatelessWidget {
  const _WiFiLockIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(160, 160),
      painter: _WiFiLockPainter(),
    );
  }
}

class _WiFiLockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final wifiPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.warning.withValues(alpha: 0.7);

    // WiFi arcs
    for (int i = 0; i < 3; i++) {
      final radius = 18.0 + i * 14;
      final rect = Rect.fromCircle(center: Offset(cx, cy - 8), radius: radius);
      canvas.drawArc(rect, -0.35 * 3.14, -0.3 * 3.14, false, wifiPaint);
    }

    // WiFi dot
    canvas.drawCircle(Offset(cx, cy - 8), 3, Paint()..color = AppColors.warning);

    // Lock body
    final lockPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.warning;

    final lockRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 24), width: 22, height: 18),
      const Radius.circular(4),
    );
    canvas.drawRRect(lockRect, lockPaint);

    // Lock shackle
    final shackle = Path()
      ..moveTo(cx - 6, cy + 15)
      ..lineTo(cx - 6, cy + 9)
      ..quadraticBezierTo(cx - 6, cy + 1, cx, cy + 1)
      ..quadraticBezierTo(cx + 6, cy + 1, cx + 6, cy + 9)
      ..lineTo(cx + 6, cy + 15);
    canvas.drawPath(shackle, lockPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlobeIllustration extends StatelessWidget {
  const _GlobeIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(160, 160),
      painter: _GlobePainter(),
    );
  }
}

class _GlobePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = 48.0;

    // Globe circle
    final globePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.primary.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx, cy), radius, globePaint);

    // Vertical ellipse (longitude)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: radius, height: radius * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.primary.withValues(alpha: 0.3),
    );

    // Horizontal line (equator)
    canvas.drawLine(
      Offset(cx - radius, cy),
      Offset(cx + radius, cy),
      Paint()
        ..strokeWidth = 1.5
        ..color = AppColors.primary.withValues(alpha: 0.3),
    );

    // Connection dots
    final dotPositions = [
      Offset(cx - 20, cy - 30),
      Offset(cx + 25, cy - 15),
      Offset(cx + 10, cy + 28),
      Offset(cx - 30, cy + 10),
    ];
    final dotPaint = Paint()..color = AppColors.primary;

    for (final pos in dotPositions) {
      canvas.drawCircle(pos, 4, dotPaint);
    }

    // Connection lines between dots
    final linePaint = Paint()
      ..strokeWidth = 1.5
      ..color = AppColors.accent.withValues(alpha: 0.5);
    canvas.drawLine(dotPositions[0], dotPositions[1], linePaint);
    canvas.drawLine(dotPositions[1], dotPositions[2], linePaint);
    canvas.drawLine(dotPositions[2], dotPositions[3], linePaint);
    canvas.drawLine(dotPositions[3], dotPositions[0], linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConnectedIllustration extends StatelessWidget {
  const _ConnectedIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(160, 160),
      painter: _ConnectedPainter(),
    );
  }
}

class _ConnectedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.connected.withValues(alpha: 0.2),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 60));
    canvas.drawCircle(Offset(cx, cy), 60, glowPaint);

    // Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.connected.withValues(alpha: 0.5),
    );

    // Inner filled circle
    canvas.drawCircle(
      Offset(cx, cy),
      34,
      Paint()..color = AppColors.connected.withValues(alpha: 0.1),
    );

    // Checkmark
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.connected;

    final check = Path()
      ..moveTo(cx - 14, cy)
      ..lineTo(cx - 4, cy + 12)
      ..lineTo(cx + 16, cy - 14);
    canvas.drawPath(check, checkPaint);

    // Small decorative dots
    final decoPaint = Paint()..color = AppColors.primary.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(cx - 55, cy - 10), 3, decoPaint);
    canvas.drawCircle(Offset(cx + 58, cy + 5), 3, decoPaint);
    canvas.drawCircle(Offset(cx + 10, cy - 55), 2, decoPaint);
    canvas.drawCircle(Offset(cx - 15, cy + 52), 2, decoPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
