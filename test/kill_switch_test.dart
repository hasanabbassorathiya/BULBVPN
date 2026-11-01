import 'package:bulbvpn/modules/core/kill_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KillSwitchStore.resetCache();
  });

  test('defaults to off so a failed connect cannot strand the phone', () async {
    expect(await KillSwitchStore.load(), isFalse);
  });

  test('persists the choice and serves it from cache', () async {
    await KillSwitchStore.save(true);
    expect(KillSwitchStore.cached, isTrue);
    KillSwitchStore.resetCache();
    expect(await KillSwitchStore.load(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('kill_switch'), isTrue);
  });

  test('turning it back off is stored as false, not removed', () async {
    await KillSwitchStore.save(true);
    await KillSwitchStore.save(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('kill_switch'), isFalse);
    KillSwitchStore.resetCache();
    expect(await KillSwitchStore.load(), isFalse);
  });
}
