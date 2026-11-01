import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Canonical external links. Keep in sync with the deployed Firebase
/// Hosting site (`site/` directory, see firebase.json).
class AppLinks {
  static const String website = 'https://bulbvpn-e9b4c.web.app';
  static const String privacy = '$website/privacy';
  static const String terms = '$website/terms';
  static const String contactEmail = 'hasanabbassorathiya12@gmail.com';

  /// Support destination (Teleform form or its Telegram hand-off). The
  /// dashboard is login-gated, so the public link is supplied at build time
  /// through `.env` / `--dart-define=SUPPORT_URL=…`. An empty value hides the
  /// row instead of opening a dead link.
  static String get supportUrl {
    const build = String.fromEnvironment('SUPPORT_URL');
    String env = '';
    try {
      env = dotenv.env['SUPPORT_URL']?.trim() ?? '';
    } catch (_) {}
    return env.isEmpty ? build.trim() : env;
  }

  static bool get hasSupport => supportUrl.isNotEmpty;
}
