/// Published catalog URLs refreshed by `.github/workflows/vpngate-servers.yml`.
///
/// The app never hits www.vpngate.net on-device. GitHub Actions pulls the
/// public CSV hourly and commits `data/vpngate.json`; clients read that file
/// from raw.githubusercontent / jsDelivr.
const List<String> vpnGatePublishedLists = <String>[
  // Current production branch (Actions + pushes land here first).
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@redesign/production-grade/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/redesign/production-grade/data/vpngate.json',
  // Default-branch fallback once catalog merges to main.
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@main/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/main/data/vpngate.json',
];
