import 'package:shared_preferences/shared_preferences.dart';

/// Records the version of the legal terms the user accepted.
///
/// Bump [currentVersion] whenever the Terms or Acceptable Use Policy change in
/// a way that needs fresh consent; the splash gate will show the screen again.
class LegalAcceptance {
  const LegalAcceptance._();

  static const String currentVersion = '2026-10-28';
  static const String _key = 'legal.accepted_version';

  static Future<bool> isAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) == currentVersion;
    } catch (_) {
      return false;
    }
  }

  static Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, currentVersion);
  }
}
