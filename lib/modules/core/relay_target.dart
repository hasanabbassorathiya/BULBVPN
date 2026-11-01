import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bulbvpn/modules/core/trust_tier.dart';

/// One relay we can actually dial, together with the country that relay is
/// published under.
///
/// The connect path and the UI must agree on this object: a tunnel is either
/// connected to [dial] or it is not. Showing a "fastest" or "selected" country
/// that the dial path did not use is what produced the US/India label with a
/// Japanese exit.
class RelayTarget {
  /// IP we hand to the tunnel. Dialling by IP keeps carrier DNS out of the
  /// handshake path.
  final String dial;

  /// TLS name used for SNI/certificate verification.
  final String sni;

  /// TCP listener the tunnel is dialled on. Relays answer SoftEther TLS on
  /// 443 as well as the alternate ports in `relay_port_agility.dart`.
  final int port;

  /// ISO-3166 alpha-2, upper case (JP, US, IN...). Empty when unknown.
  final String countryCode;

  /// Human readable country from the catalog (e.g. "Japan").
  final String countryName;

  /// Latency measured from this device, or the catalog value when unmeasured.
  final int pingMs;

  /// Why this target is in the list: selected / fastest / last-good / proven.
  final String source;

  /// Who operates the exit. Only set when the target came from a source that
  /// can prove it (catalog trust tiers, REALITY catalogs); `null` means the
  /// UI must not claim either way.
  final TrustTier? trustTier;

  const RelayTarget({
    required this.dial,
    required this.sni,
    this.port = 443,
    this.countryCode = '',
    this.countryName = '',
    this.pingMs = 0,
    this.source = 'fastest',
    this.trustTier,
  });

  RelayTarget copyWith({
    String? dial,
    String? sni,
    int? port,
    String? countryCode,
    String? countryName,
    int? pingMs,
    String? source,
    TrustTier? trustTier,
  }) {
    return RelayTarget(
      dial: dial ?? this.dial,
      sni: sni ?? this.sni,
      port: port ?? this.port,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      pingMs: pingMs ?? this.pingMs,
      source: source ?? this.source,
      trustTier: trustTier ?? this.trustTier,
    );
  }

  String get code {
    final value = countryCode.trim().toLowerCase();
    return value.length == 2 ? value : '';
  }

  /// Never expose the relay hostname/address in the private UI.
  String get displayName {
    final name = countryName.trim();
    if (name.isNotEmpty) return name;
    final upper = countryCode.trim().toUpperCase();
    if (upper.length == 2) return upper;
    return 'Private relay';
  }

  bool sameCountry(String? code) {
    final other = (code ?? '').trim().toUpperCase();
    return other.length == 2 && other == countryCode.trim().toUpperCase();
  }

  String get label => '${displayName.toUpperCase()} · $dial';

  /// `ip:port`, or the bare ip when the relay is on the primary listener so
  /// logs and the home screen stay quiet about the default.
  String get endpoint => port == 443 ? dial : '$dial:$port';

  @override
  String toString() => 'RelayTarget($label, sni=$sni, port=$port, $source)';
}

/// The relay that is actually carrying packets right now.
///
/// `null` means no live tunnel. It is cleared on every disconnect/failure so
/// the UI can never render a stale country or flag.
final connectedRelayProvider = StateProvider<RelayTarget?>((ref) => null);
