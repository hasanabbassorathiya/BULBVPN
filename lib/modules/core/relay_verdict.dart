/// What a measurement actually establishes about a relay.
///
/// One vocabulary, printed by both the connect card's tariff sheet and the
/// relay slip, because the same host cannot be `OK` on one face and a caveat on
/// the other. The distinction that matters here is the one this app used to get
/// backwards: a TLS handshake answering is not a tunnel carrying.
enum RelayVerdict {
  /// Bytes crossed this relay on this device. The only verdict that says the
  /// path works.
  carried,

  /// Someone else's probe moved bytes through it. A fact about a datacenter,
  /// not about the network this phone is on.
  probed,

  /// Something answered and nothing was carried. Printed rather than rounded up
  /// to `OK`: a relay with a good handshake and no traffic is exactly the relay
  /// that used to win this list.
  unproven,

  /// A measurement came back refused or empty.
  blocked,

  /// No measurement yet, or one still in flight.
  untried;

  /// The word the plate prints in the STATE column.
  String get word => switch (this) {
    RelayVerdict.carried => 'CARRIED',
    RelayVerdict.probed => 'PROBED',
    RelayVerdict.unproven => 'NOT PROVEN',
    RelayVerdict.blocked => 'BLOCKED',
    RelayVerdict.untried => '—',
  };

  /// A relay that was measured and did not deliver. The row is printed in the
  /// plate's warm red for the whole width, because the finding is about the
  /// relay, not about one cell of it.
  bool get failed => this == RelayVerdict.blocked;

  /// Print that is present but must not be read as a promise.
  bool get quiet =>
      this == RelayVerdict.untried || this == RelayVerdict.unproven;
}
