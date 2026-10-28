/// Published catalog URLs refreshed by `.github/workflows/vpngate-servers.yml`.
///
/// The app never hits www.vpngate.net on-device. GitHub Actions pulls the
/// public CSV hourly and commits `data/vpngate.json`; clients read that file
/// from raw.githubusercontent / jsDelivr.
const List<String> vpnGatePublishedLists = <String>[
  // Default branch is the only branch GitHub runs the hourly cron on, so its
  // file is the freshest one. (The workflow was never merged here until
  // 2026-10-28; keep this first so a merged pipeline wins.)
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@main/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/main/data/vpngate.json',
  // Current production branch fallback while main is stale/absent.
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@redesign/production-grade/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/redesign/production-grade/data/vpngate.json',
];
