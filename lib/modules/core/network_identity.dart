import 'dart:io';

/// Identity of the network the phone is using right now, without
/// `connectivity_plus` (its native registration SIGSEGVs on iOS 27 beta).
///
/// The fingerprint is deliberately coarse:
/// * Wi-Fi is keyed by interface plus its /24, so home and office differ.
/// * Cellular is keyed by the data interface only, because carriers rotate
///   CGNAT addresses between sessions.
/// * Tunnel interfaces are ignored; this describes the carrier beneath them.
class NetworkIdentity {
  NetworkIdentity._();

  static String? _cached;
  static DateTime? _cachedAt;

  static Future<String> current({bool fresh = false}) async {
    final now = DateTime.now();
    if (!fresh &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!).inSeconds < 5) {
      return _cached!;
    }
    final value = await _read();
    _cached = value;
    _cachedAt = now;
    return value;
  }

  static Future<String> _read() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      String? wifi;
      String? cell;
      String? wired;
      var wifiScore = 1 << 20;
      var cellScore = 1 << 20;
      var wiredScore = 1 << 20;
      for (final iface in interfaces) {
        if (!_carriesInternet(iface.name) || iface.addresses.isEmpty) continue;
        final family = _family(iface.name);
        if (family == 'wifi') {
          final score = _wifiScore(iface.name);
          if (score < wifiScore) {
            wifiScore = score;
            final prefix = _prefix(iface.addresses.first.address, 3);
            wifi = 'wifi:${iface.name}:$prefix';
          }
        } else if (family == 'cell') {
          final score = _cellScore(iface.name);
          if (score < cellScore) {
            cellScore = score;
            cell = 'cell:${iface.name}';
          }
        } else if (family == 'eth') {
          final score = iface.name == 'eth0' ? 0 : 5;
          if (score < wiredScore) {
            wiredScore = score;
            wired = 'eth:${iface.name}';
          }
        }
      }
      final parts = [wifi, cell, wired].whereType<String>().toList()..sort();
      if (parts.isEmpty) return 'offline';
      return parts.join('|');
    } catch (_) {
      return 'unknown';
    }
  }

  static bool _carriesInternet(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('tun') ||
        n.startsWith('utun') ||
        n.startsWith('ppp') ||
        n.startsWith('ipsec') ||
        n.startsWith('tap') ||
        n == 'lo') {
      return false;
    }
    return true;
  }

  static String _family(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('en') ||
        n.startsWith('wlan') ||
        n.startsWith('wl') ||
        n.contains('wi-fi')) {
      return 'wifi';
    }
    if (n.startsWith('pdp_ip') ||
        n.startsWith('rmnet') ||
        n.startsWith('ccmni') ||
        n.startsWith('wwan') ||
        n.startsWith('pdp')) {
      return 'cell';
    }
    if (n.startsWith('eth')) return 'eth';
    return 'other';
  }

  /// Prefer the interface that carries internet traffic. Android exposes
  /// separate IMS/MMS rmnet interfaces that appear and disappear without a
  /// real handover; including them makes the fingerprint flap.
  static int _wifiScore(String name) {
    final n = name.toLowerCase();
    if (n == 'en0' || n == 'wlan0') return 0;
    if (n.contains('wlan') || n.startsWith('en')) return 1;
    return 5;
  }

  static int _cellScore(String name) {
    final n = name.toLowerCase();
    if (n == 'pdp_ip0') return 0;
    if (n.contains('data0')) return 1;
    if (n.contains('data')) return 2;
    if (n.contains('ims') || n.contains('mms')) return 100;
    return 10;
  }

  static String _prefix(String ip, int octets) {
    final parts = ip.split('.');
    if (parts.length < octets) return ip;
    return parts.take(octets).join('.');
  }
}
