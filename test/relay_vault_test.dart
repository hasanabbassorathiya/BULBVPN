import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_link.dart';
import 'package:bulbvpn/modules/core/reality/relay_vault.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';

/// The vault is the only place a user's own server survives a restart, so these
/// tests are about what is kept and what is dropped: an import that looks
/// successful and then loses the relay on the next launch is the same betrayal
/// as a connect that reports success with no bytes behind it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RelayVault.resetCache();
  });

  test('a pasted link survives a restart and is still dialable', () async {
    final relay = relayFromLink(
      'trojan://s3cret@grpc.example.net:443?security=tls'
      '&sni=grpc.example.net&type=grpc&serviceName=video#Home',
    )!;
    await RelayVault.merge([relay]);
    RelayVault.resetCache();

    final restored = await RelayVault.load();
    expect(restored, hasLength(1));
    final back = restored.single;
    expect(back.id, 'Home');
    expect(back.host, 'grpc.example.net');
    expect(back.port, 443);
    expect(back.link, relay.link);
    expect(back.private, isTrue);

    final outbound =
        ((back.toXrayConfig()['outbounds']! as List).single
            as Map<String, Object?>);
    expect(outbound['tag'], 'proxy');
    expect(outbound['protocol'], 'trojan');
    // The shape the sheet previews did not drift across the round trip.
    expect(DialShape.of(back).summary, 'Trojan · gRPC · TLS');
  });

  test('re-importing an address replaces it instead of stacking a twin', () async {
    final first = relayFromLink(
      'vless://aaaa-1111@one.example.net:443?encryption=none&security=tls#Old',
    )!;
    await RelayVault.merge([first]);
    final renamed = relayFromLink(
      'vless://bbbb-2222@one.example.net:443?encryption=none&security=tls#New',
    )!;
    final merged = await RelayVault.merge([renamed]);

    expect(merged, hasLength(1));
    expect(merged.single.id, 'New');
    expect(merged.single.link, renamed.link);
    // The uuid changed under the same address, and the vault holds the profile
    // the user pasted last rather than the one that already failed.
    expect(merged.single.toXrayConfigJson().contains('bbbb-2222'), isTrue);
  });

  test('removal is by id and clearing leaves nothing behind', () async {
    final a = relayFromLink('trojan://x@a.example.net:443?security=tls#A')!;
    final b = relayFromLink('trojan://y@b.example.net:443?security=tls#B')!;
    await RelayVault.merge([a, b]);

    final after = await RelayVault.remove('A');
    expect(after.map((relay) => relay.id), ['B']);

    await RelayVault.clear();
    expect(RelayVault.cached, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    // A clear that leaves the key in preferences is a clear that un-does itself
    // on the next launch, and an imported link is a credential.
    expect(prefs.getKeys().contains('bulb_relay_vault_v1'), isFalse);
  });

  test('an unreadable body is dropped whole, not half-restored', () {
    expect(RelayVault.parse('not json'), isEmpty);
    expect(RelayVault.parse('{"relays":[]}'), isEmpty);

    final rows = [
      const {'id': 'good', 'host': 'g.example.net', 'port': 443},
      // No link and no REALITY fields: nothing this build can dial.
      const {'id': 'hollow', 'host': 'h.example.net', 'port': 443},
      const {'id': 'no-port', 'host': 'p.example.net', 'port': 0},
      {'id': 'row', 'host': 'r.example.net', 'port': 2053, 'link': _wsLink()},
    ];
    final relays = RelayVault.parse(jsonEncode(rows));
    expect(relays.map((relay) => relay.id), ['row']);

    // A row that is addressable but no longer parseable keeps its id, so the
    // sheet can still offer to remove it.
    const unparseable = {
      'id': 'legacy',
      'host': 'l.example.net',
      'port': 443,
      'uuid': 'u',
      'public_key': 'k',
      'server_name': 'l.example.net',
    };
    final legacy = RelayVault.parse(jsonEncode([unparseable]));
    expect(legacy.single.id, 'legacy');
    expect(legacy.single.link, isNull);
    expect(DialShape.of(legacy.single).summary, 'VLESS · TCP · REALITY');
  });

  test('the vault holds its ceiling rather than a scraped list', () async {
    final rows = List.generate(
      RelayVault.maxRelays + 50,
      (i) => {
        'id': 'r$i',
        'host': 'h$i.example.net',
        'port': 443,
        'link': 'trojan://p@h$i.example.net:443?security=tls#r$i',
      },
    );
    final relays = RelayVault.parse(jsonEncode(rows));
    expect(relays, hasLength(RelayVault.maxRelays));

    final incoming = List.generate(
      RelayVault.maxRelays + 50,
      (i) => relayFromLink(
        'trojan://p@n$i.example.net:443?security=tls#n$i',
      )!,
    );
    final merged = await RelayVault.merge(incoming);
    expect(merged.length <= RelayVault.maxRelays, isTrue);
  });

  test('an imported relay is private and a catalog one is not', () async {
    final imported = relayFromLink('trojan://p@v.example.net:443?security=tls')!;
    await RelayVault.merge([imported]);
    final back = (await RelayVault.load()).single;
    expect(back.toTarget().trustTier, TrustTier.byos);
    expect(back.toTarget().trustTier!.isPrivate, isTrue);

    const catalog = RealityRelay(
      id: 'c',
      host: 'c.example.net',
      port: 443,
      uuid: 'u',
      publicKey: 'k',
      serverName: 'www.apple.com',
    );
    expect(catalog.toTarget().trustTier, TrustTier.community);
  });

  test('load on an empty vault is empty, not an exception', () async {
    expect(await RelayVault.load(), isEmpty);
    expect(RelayVault.cached, isEmpty);
  });

  test('an import that lands during hydration is not un-done by it', () async {
    // The first preferences read of a launch is still in flight when the user
    // pastes a link, so two reads of the same file are running at once. The one
    // that started first sees the old (empty) vault and finishes last; if it is
    // allowed to publish what it read, the phone forgets the server the user
    // just added — the sheet goes back to "Add your own server" while the
    // import really did succeed on disk.
    final hydrating = RelayVault.load();
    final relay = relayFromLink('trojan://p@race.example.net:443?security=tls#Race')!;
    final merged = await RelayVault.merge([relay]);
    expect(merged, hasLength(1));

    await hydrating;
    expect(RelayVault.cached.map((r) => r.id), ['Race']);
    expect(await RelayVault.load(), hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bulb_relay_vault_v1'), contains('Race'));
  });
}

String _wsLink() =>
    'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11@ws.example.net:2053'
    '?encryption=none&security=tls&sni=cdn.example.net'
    '&type=ws&path=%2Fws-path#WS-2053';
