import 'package:bulbvpn/modules/core/watchdog_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one miss is not a dead tunnel', () {
    final policy = WatchdogPolicy();
    expect(policy.record(ok: false), isFalse);
    expect(policy.misses, 1);
    expect(policy.verified, isFalse);
  });

  test('two consecutive misses drop the session', () {
    final policy = WatchdogPolicy();
    policy.record(ok: false);
    expect(policy.record(ok: false), isTrue);
  });

  test('a success between misses resets the streak', () {
    final policy = WatchdogPolicy();
    policy.record(ok: false);
    policy.record(ok: true);
    expect(policy.misses, 0);
    expect(policy.verified, isTrue);
    expect(policy.record(ok: false), isFalse);
  });

  test('verified stays true after a later miss', () {
    final policy = WatchdogPolicy();
    policy.record(ok: true);
    policy.record(ok: false);
    expect(policy.verified, isTrue);
    expect(policy.misses, 1);
  });

  test('reset starts a new session at zero', () {
    final policy = WatchdogPolicy();
    policy.record(ok: true);
    policy.record(ok: false);
    policy.reset();
    expect(policy.misses, 0);
    expect(policy.verified, isFalse);
  });

  test('the threshold is configurable for tests and tuning', () {
    final policy = WatchdogPolicy(missesToDrop: 3);
    expect(policy.record(ok: false), isFalse);
    expect(policy.record(ok: false), isFalse);
    expect(policy.record(ok: false), isTrue);
  });
}
