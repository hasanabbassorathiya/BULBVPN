import 'dart:convert';

import 'package:bulbvpn/modules/core/reality/reality_health.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/main/application/relay_evidence_provider.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anchored to the wall clock because [RealityHealth.usable] reads
/// `DateTime.now()` on its own; a fixed timestamp would go stale with the day.
final _t0 = DateTime.now();

RealityHealth _health(List<Map<String, Object?>> probes) {
  return RealityHealth.parse(
    jsonEncode({
      'schema': RealityHealth.schema,
      'generated_at': _t0.toUtc().toIso8601String(),
      'probes': probes,
    }),
  )!;
}

SessionProof _proof(String dial, int bytesPerSecond, {int hoursAgo = 0}) {
  return SessionProof(
    dial: dial,
    bytesPerSecond: bytesPerSecond,
    at: _t0.subtract(Duration(hours: hoursAgo)),
  );
}

void main() {
  final fleet = _health([
    {'id': 'r-good', 'ok': true, 'bytes': 400000, 'ms': 2000},
    {'id': 'r-dead', 'ok': false, 'bytes': 0, 'ms': 0},
  ]);

  group('RelayEvidence.reading', () {
    test('names a handshake as a handshake when nothing else is known', () {
      const evidence = RelayEvidence(proven: {}, health: null);
      final reading = evidence.reading(
        dial: '10.0.0.1',
        ping: const ServerPing.ok(40),
        now: _t0,
      );

      expect(reading.kind, ReadingKind.handshake);
      expect(reading.value, '40 ms');
      // The qualifier is the whole point: 40 ms alone reads like a speed.
      expect(reading.qualifier, 'TLS only');
    });

    test('an own session outranks a fleet probe and a fast handshake', () {
      final evidence = RelayEvidence(
        proven: {'10.0.0.1': _proof('10.0.0.1', 900000, hoursAgo: 4)},
        health: fleet,
      );
      final reading = evidence.reading(
        dial: '10.0.0.1',
        relayId: 'r-good',
        ping: const ServerPing.ok(40),
        now: _t0,
      );

      expect(reading.kind, ReadingKind.ownSession);
      expect(reading.value, '879 KB/s');
      expect(reading.qualifier, 'you · 4 h');
    });

    test('a fleet probe is labelled as someone else\'s measurement', () {
      const absent = RelayEvidence(proven: {}, health: null);
      final measured = RelayEvidence(proven: {}, health: fleet);
      final reading = measured.reading(
        relayId: 'r-good',
        ping: const ServerPing.ok(30),
        now: _t0,
      );

      expect(reading.kind, ReadingKind.fleetProbe);
      expect(reading.value, '195 KB/s');
      expect(reading.qualifier, startsWith('probe'));
      expect(absent.fleetFor('r-good'), isNull);
    });

    test('a relay the fleet measured dead is not rescued by its handshake', () {
      final evidence = RelayEvidence(proven: {}, health: fleet);
      final reading = evidence.reading(
        relayId: 'r-dead',
        ping: const ServerPing.ok(35),
        now: _t0,
      );

      // This is the failure the ranking existed to close: a short TLS round
      // trip used to sit above the evidence that no session ever completed.
      expect(reading.kind, ReadingKind.probeFailed);
      expect(reading.value, '—');
      expect(reading.qualifier, 'probe failed');
    });

    test('nothing measured prints a dash, never a blank or a guess', () {
      const evidence = RelayEvidence(proven: {}, health: null);

      expect(evidence.reading(dial: 'nope', now: _t0).kind, ReadingKind.none);
      expect(evidence.reading(dial: 'nope').value, '—');
      expect(evidence.reading(dial: 'nope').qualifier, 'not measured');
    });

    test('a sweep in flight says so instead of showing a stale number', () {
      const evidence = RelayEvidence(proven: {}, health: null);
      final reading = evidence.reading(
        dial: '10.0.0.9',
        ping: ServerPing.pending,
        now: _t0,
      );

      expect(reading.kind, ReadingKind.measuring);
      expect(reading.value, '—');
      expect(reading.qualifier, 'measuring');
    });

    test('a proof from this minute says now, not 0 min', () {
      final evidence = RelayEvidence(
        proven: {'10.0.0.1': _proof('10.0.0.1', 40000)},
        health: null,
      );

      expect(
        evidence.reading(dial: '10.0.0.1', now: _t0).qualifier,
        'you · now',
      );
    });
  });

  test('proofs are keyed by dial so both engines can be asked together', () {
    final evidence = RelayEvidence(
      proven: {
        '10.0.0.1': _proof('10.0.0.1', 40000, hoursAgo: 2),
        'reality.example': _proof('reality.example', 900000),
      },
      health: null,
    );

    expect(evidence.isProven('10.0.0.1'), isTrue);
    expect(evidence.isProven('reality.example'), isTrue);
    expect(evidence.isProven('10.0.0.2'), isFalse);
    expect(evidence.proven.keys.toSet(), hasLength(2));
  });
}
