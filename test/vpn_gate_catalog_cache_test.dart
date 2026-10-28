import 'package:bulbvpn/modules/core/vpn_gate_candidates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Candidate candidate(String ip, {String countryCode = 'JP'}) => Candidate(
    ip: ip,
    port: 443,
    protocol: 'tcp',
    csvPing: 30,
    b64: '',
    config: 'client\ndev tun\nremote $ip 443\nproto tcp\n<ca></ca>\n',
    sni: 'public-vpn-1.opengw.net',
    countryCode: countryCode,
    countryName: 'Japan',
  );

  test('round-trips the engine-ready catalog', () async {
    await VpnGateCatalogCache.save([
      candidate('203.0.113.7'),
      candidate('203.0.113.8', countryCode: 'DE'),
    ]);

    final loaded = await VpnGateCatalogCache.load();

    expect(loaded, hasLength(2));
    expect(loaded.first.ip, '203.0.113.7');
    expect(loaded.first.protocol, 'tcp');
    expect(loaded.first.config, contains('remote 203.0.113.7 443'));
    expect(loaded.first.b64, isEmpty);
    expect(loaded.last.countryCode, 'DE');
  });

  test('a catalog older than a week is not used', () async {
    final at = DateTime(2026, 10, 1, 12);
    await VpnGateCatalogCache.save([candidate('203.0.113.7')], now: at);

    expect(
      await VpnGateCatalogCache.load(now: at.add(const Duration(days: 6))),
      hasLength(1),
    );
    expect(
      await VpnGateCatalogCache.load(now: at.add(const Duration(days: 8))),
      isEmpty,
    );
  });

  test('entries without a config are skipped', () async {
    await VpnGateCatalogCache.save([
      const Candidate(
        ip: '203.0.113.9',
        port: 443,
        protocol: 'tcp',
        csvPing: 0,
        b64: '',
        config: '',
      ),
      candidate('203.0.113.7'),
    ]);

    final loaded = await VpnGateCatalogCache.load();
    expect(loaded.map((c) => c.ip), ['203.0.113.7']);
  });

  test('the cache never grows past its bound', () async {
    await VpnGateCatalogCache.save([
      for (var i = 0; i < 70; i++) candidate('203.0.$i.1'),
    ]);

    final loaded = await VpnGateCatalogCache.load();
    expect(loaded, hasLength(60));
    expect(loaded.first.ip, '203.0.0.1');
  });
}
