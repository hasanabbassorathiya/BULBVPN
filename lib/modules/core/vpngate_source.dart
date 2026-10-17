/// Published VPN Gate lists, refreshed by `.github/workflows/vpngate-servers.yml`.
///
/// GitHub is reachable from networks that drop www.vpngate.net. The feature
/// branch copy is listed first until this file also exists on `main`.
const List<String> vpnGatePublishedLists = <String>[
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/redesign/production-grade/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/main/data/vpngate.json',
];
