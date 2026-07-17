import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'l10n/app_localizations.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ad_provider.dart';
import 'providers/subscription_provider.dart';
import 'screens/home_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'constants/app_theme.dart';
import 'services/storage_service.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable semantics for accessibility and testing
  if (kDebugMode) {
    SemanticsBinding.instance.ensureSemantics();
  }

  // Initialize Firebase synchronously — required before any Firebase usage
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize crashlytics
  await CrashlyticsService().initialize();

  // Initialize notifications
  await NotificationService().initialize();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Log app open
  AnalyticsService().logAppOpen();

  runApp(const BulbVPNApp());
}

class BulbVPNApp extends StatefulWidget {
  const BulbVPNApp({super.key});
  @override
  State<BulbVPNApp> createState() => _BulbVPNAppState();
}

class _BulbVPNAppState extends State<BulbVPNApp> {
  late VPNProvider _vpnProvider;
  late AuthProvider _authProvider;
  late AdProvider _adProvider;
  late SubscriptionProvider _subscriptionProvider;
  bool _initialized = false;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _vpnProvider = VPNProvider();
    _authProvider = AuthProvider();
    _adProvider = AdProvider();
    _subscriptionProvider = SubscriptionProvider();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load local settings immediately (fast, no network)
    final storage = StorageService();
    await storage.initialize();
    _onboardingComplete = storage.onboardingComplete;

    // Set initialized to show the app immediately
    if (mounted) setState(() => _initialized = true);

    // Defer heavy network operations to background
    // Don't await — let them run independently
    _vpnProvider.initialize().then((_) {
      _subscriptionProvider.initialize();
      _adProvider.initialize();
      _adProvider.setShowAds(!_subscriptionProvider.hasNoAds);
    });
  }

  @override
  void dispose() {
    _vpnProvider.dispose();
    _authProvider.dispose();
    _adProvider.dispose();
    _subscriptionProvider.dispose();
    super.dispose();
  }

  Widget _resolveHome() {
    if (!_initialized) {
      AnalyticsService().logScreenView(screenName: 'splash');
      return const _SplashScreen();
    }
    if (!_onboardingComplete) {
      AnalyticsService().logScreenView(screenName: 'onboarding');
      return OnboardingScreen(
        onComplete: () {
          setState(() => _onboardingComplete = true);
        },
      );
    }
    AnalyticsService().logScreenView(screenName: 'main_navigation');
    return const MainNavigation();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _vpnProvider),
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _adProvider),
        ChangeNotifierProvider.value(value: _subscriptionProvider),
      ],
      child: Consumer<VPNProvider>(
        builder: (context, vpn, _) {
          return MaterialApp(
            title: 'BULB VPN',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: vpn.darkMode ? ThemeMode.dark : ThemeMode.light,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'),
              Locale('es'),
              Locale('pt'),
            ],
            home: _resolveHome(),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.bgDark, AppColors.bgSurface],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt_rounded, size: 80, color: AppColors.primary),
              SizedBox(height: 16),
              Text('BULB VPN', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2)),
              SizedBox(height: 8),
              Text('Fast. Secure. Private.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              SizedBox(height: 32),
              CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [HomeScreen(), ServersScreen(), StatsScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _screens[_currentIndex]),
      bottomNavigationBar: _buildNavBar(colors),
    );
  }

  Widget _buildNavBar(AppSemanticColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 10))],
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, Icons.home_rounded, Icons.home_outlined, 'Home', colors),
          _navItem(1, Icons.dns_rounded, Icons.dns_outlined, 'Servers', colors),
          _navItem(2, Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Stats', colors),
          _navItem(3, Icons.settings_rounded, Icons.settings_outlined, 'Settings', colors),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData icon, String label, AppSemanticColors colors) {
    final sel = _currentIndex == index;
    return Semantics(
      label: '$label tab',
      button: true,
      selected: sel,
      child: GestureDetector(
        onTap: () {
          if (!sel) {
            final screenNames = ['home', 'servers', 'stats', 'settings'];
            AnalyticsService().logScreenView(screenName: screenNames[index]);
          }
          setState(() => _currentIndex = index);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: sel ? 18 : 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sel ? activeIcon : icon, color: sel ? AppColors.primary : colors.textMuted, size: 24),
            if (sel) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
