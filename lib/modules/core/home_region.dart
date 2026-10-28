import 'dart:io';

/// Best-effort answer to "which country is this phone in".
///
/// Region-locked services read the exit IP's country. Auto mode used to pick
/// the lowest-ping relay, which on an Iranian carrier is frequently an Iranian
/// VPN Gate exit: the tunnel works, but every site still sees the local
/// region. This value lets the relay plan put foreign exits first without
/// removing the local ones (a local relay is still better than no tunnel).
///
/// The signal is the system locale's country, with a timezone fallback for
/// Iran (+03:30 is unique). It is a heuristic, not an authority: a phone with
/// an en_US locale in Tehran is caught by the timezone, and a user who wants a
/// specific country can always pick it explicitly.
class HomeRegion {
  HomeRegion._();

  static final String? _country = _detect();

  static String? get countryCode => _country;

  static String get locale => Platform.localeName;

  /// `+3:30` style offset of the device clock.
  static String get timezone {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '$sign${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static bool isHome(String countryCode) {
    final code = countryCode.trim().toUpperCase();
    final home = _country;
    return home != null && code.length == 2 && code == home;
  }

  static String? _detect() {
    // +03:30 is unique to Iran, and the timezone survives an English phone
    // locale — the common case for an Iranian user whose system language is
    // not Persian. Check it before the locale.
    final now = DateTime.now();
    final zoneName = now.timeZoneName.toLowerCase();
    if (zoneName.contains('tehran') || zoneName.contains('iran')) return 'IR';
    if (now.timeZoneOffset == const Duration(hours: 3, minutes: 30)) {
      return 'IR';
    }
    final parts = Platform.localeName.replaceAll('-', '_').split('_');
    if (parts.length >= 2) {
      // zh_Hant_TW carries a script between language and region.
      final candidate = parts[1].length == 4 && parts.length > 2
          ? parts[2]
          : parts[1];
      final code = candidate.trim().toUpperCase();
      if (RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
    }
    return null;
  }
}
