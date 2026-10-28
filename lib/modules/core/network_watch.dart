import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_identity.dart';

/// Emits the carrier network fingerprint whenever Wi-Fi/cellular changes.
///
/// connectivity_plus is deliberately not used: its native registration
/// SIGSEGVs on iOS 27 beta (see [NetworkIdentity]). This polls the same
/// interface list the relay memory already keys on, so one signal drives both
/// the relay pick and the UI refreshes.
final networkFingerprintProvider = StreamProvider<String>((ref) async* {
  var last = await NetworkIdentity.current(fresh: true);
  yield last;
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 5));
    final next = await NetworkIdentity.current(fresh: true);
    if (next == last) continue;
    last = next;
    yield next;
  }
});
