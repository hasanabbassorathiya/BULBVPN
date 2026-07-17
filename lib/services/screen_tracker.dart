import 'analytics_service.dart';

class ScreenTracker {
  static final ScreenTracker _instance = ScreenTracker._();
  factory ScreenTracker() => _instance;
  ScreenTracker._();

  String _currentScreen = '';

  void track(String screenName, {String? screenClass}) {
    if (_currentScreen == screenName) return;
    _currentScreen = screenName;
    AnalyticsService().logScreenView(screenName: screenName, screenClass: screenClass);
  }
}
