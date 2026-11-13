/// Published catalog URLs refreshed by `.github/workflows/vpngate-servers.yml`.
///
/// The app never hits www.vpngate.net on-device. GitHub Actions pulls the
/// public CSV hourly and commits `data/vpngate.json`; clients read that file
/// from raw.githubusercontent / jsDelivr.
const List<String> vpnGatePublishedLists = <String>[
  // The default branch is the only branch GitHub runs the hourly cron on, so
  // its file is the freshest one — once the workflow is actually merged there.
  // Measured 2026-11-06 both of these answer 404, because `origin/main` is at
  // a 2026-07-18 tip that carries neither `.github/workflows/` nor `data/`.
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@main/data/vpngate.json',
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/main/data/vpngate.json',
  // The branch this build ships from. It has to be listed and kept current:
  // the first URL that returns rows wins, and the entry that was here before
  // (`@redesign/production-grade`) is a frozen 2026-10-18 roster that silently
  // beat the 2026-10-28 one this branch publishes.
  'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/feat/greatest-vpn/data/vpngate.json',
  'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@feat/greatest-vpn/data/vpngate.json',
];
