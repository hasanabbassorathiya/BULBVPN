import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bulbvpn/modules/core/reality/reality_engine.dart';

/// The engine that survives Iranian mobile-data DPI is only reached if the
/// settings let it run, so the default is the difference between a connect that
/// fails on a blackholed protocol and a connect that has somewhere to go.
void main() {
  group('the censorship-resistant engine default', () {
    test('a device with no recorded choice may attempt REALITY', () {
      expect(const RealitySettings().enabled, isTrue);
      expect(const RealitySettings().usable, isTrue);
    });

    test('a choice to turn it off is remembered as off', () async {
      SharedPreferences.setMockInitialValues({
        'bulb_reality_v1': '{"enabled":false}',
      });
      RealitySettingsStore.resetCache();
      addTearDown(RealitySettingsStore.resetCache);
      final settings = await RealitySettingsStore.load();
      expect(settings.enabled, isFalse);
      expect(settings.usable, isFalse);
    });

    test('a device with a picked relay is usable whatever the switch says', () {
      final settings = RealitySettings.fromJson({'enabled': false, 'selected': 'r-1'});
      expect(settings.selectedId, 'r-1');
      expect(settings.usable, isTrue);
    });

    test('an unreadable record cannot strand the engine off', () async {
      SharedPreferences.setMockInitialValues({'bulb_reality_v1': 'not json'});
      RealitySettingsStore.resetCache();
      addTearDown(RealitySettingsStore.resetCache);
      expect((await RealitySettingsStore.load()).usable, isTrue);
    });
  });
}
