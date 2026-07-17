import 'package:flutter_test/flutter_test.dart';
import 'package:bulbvpn/models/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('builds valid WireGuard config', () {
      const config = ServerConfig(
        id: 'us-ny-1',
        name: 'New York',
        country: 'United States',
        countryCode: 'US',
        flag: '🇺🇸',
        endpoint: 'us-ny.bulbvpn.com',
        port: 51820,
        publicKey: 'TEST_PUBLIC_KEY',
        internalAddress: '10.0.0.1',
      );

      final wgConfig = config.buildConfig('TEST_PRIVATE_KEY');

      expect(wgConfig, contains('[Interface]'));
      expect(wgConfig, contains('PrivateKey = TEST_PRIVATE_KEY'));
      expect(wgConfig, contains('Address = 10.0.0.1/32'));
      expect(wgConfig, contains('[Peer]'));
      expect(wgConfig, contains('PublicKey = TEST_PUBLIC_KEY'));
      expect(wgConfig, contains('Endpoint = us-ny.bulbvpn.com:51820'));
      expect(wgConfig, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
      expect(wgConfig, contains('PersistentKeepalive = 25'));
    });

    test('includes preshared key when provided', () {
      const config = ServerConfig(
        id: 'test',
        name: 'Test',
        country: 'Test',
        countryCode: 'T1',
        flag: '🏳️',
        endpoint: 'test.com',
        publicKey: 'PUB_KEY',
        presharedKey: 'PSK_KEY',
        internalAddress: '10.0.0.1',
      );

      final wgConfig = config.buildConfig('PRIV_KEY');
      expect(wgConfig, contains('PresharedKey = PSK_KEY'));
    });

    test('serializes to and from JSON', () {
      const config = ServerConfig(
        id: 'us-ny-1',
        name: 'New York',
        country: 'United States',
        countryCode: 'US',
        flag: '🇺🇸',
        endpoint: 'us-ny.bulbvpn.com',
        publicKey: 'KEY',
        internalAddress: '10.0.0.1',
        isPremium: true,
      );

      final json = config.toJson();
      final restored = ServerConfig.fromJson(json);

      expect(restored.id, config.id);
      expect(restored.name, config.name);
      expect(restored.isPremium, true);
    });
  });
}
