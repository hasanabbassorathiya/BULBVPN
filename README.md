# BULBVPN

Private VPN client for Android, iOS, macOS, and Windows. Built with Flutter.
It dials OpenVPN first, keeps a live tunnel across network changes, and falls
back to SoftEther when that path is the one that forwards.

The phone and tablet apps do not download the server list from VPN Gate.
GitHub Actions refreshes a catalog in this repo, and connect resolves names
with DNS-over-HTTPS.

## Features

- One-tap connect and disconnect
- Hourly server catalog from GitHub Actions (`data/vpngate.json`)
- DNS-over-HTTPS (Cloudflare, then Google) before a hostname is dialed
- Device-side server ping with the fastest relay on top
- OpenVPN-first connect, with a SoftEther TLS 1.0 path for VPN Gate relays
- Signed macOS app (`bulbvpn.app`) with the same packet-tunnel provider
- Session restore when you reopen the app while the tunnel is still up
- Built-in Cloudflare speed test
- Private UI: country labels only, no public relay hostnames on the home screen
- Release builds hide the in-app log. Debug builds still have the log button.

## Platforms

| Platform | Status |
| --- | --- |
| Android | Play package `app.bulbvpn.com` |
| iOS | Packet tunnel, iPhone and iPad, TestFlight / App Store |
| macOS | Signed `bulbvpn.app` (`flutter build macos --release`) |
| Windows | Bundled OpenVPN + TAP; run the release script on Windows |

## Server catalog and DNS

`.github/workflows/vpngate-servers.yml` runs hourly (and on demand). It
fetches the public server CSV with `scripts/fetch_vpngate.py` and commits
`data/vpngate.json` when the list changes. Clients load that file from
jsDelivr and raw GitHub. They do not call VPN Gate on the device.

When a relay is a hostname, `DohResolver` asks Cloudflare DNS-over-HTTPS,
then Google, and dials the IPv4 answer.

## macOS app

```bash
flutter build macos --release
open build/macos/Build/Products/Release/bulbvpn.app
```

The packet tunnel is `macos/PacketTunnel`. SoftEther TLS fixes are applied
after `pod install` by `scripts/patch_openvpn_adapter.sh` (see
`patches/openvpn_adapter/`).

## Logs

Release and profile builds do not show the log panel (`kDebugMode` is false).
Connection traces stay in the debug build and in the packet-tunnel file log
used while developing. They are not part of the release UI.

## Requirements

- Flutter SDK ≥ 3.44 (see `.fvmrc`)
- Xcode 16+ for iOS / macOS
- Android Studio / JDK 17 for Android
- Apple Developer team for iOS signing
- Play Console upload key for Android release

## Setup

```bash
flutter pub get
flutter run
```

iOS needs CocoaPods:

```bash
cd ios && pod install && cd ..
```

## Release

Build every platform this machine can sign, then optionally publish a GitHub
release:

```bash
./scripts/release_all.sh          # build only
./scripts/release_all.sh --github # build + gh release create
```

Artifacts land in `dist/v<version>-<build>/`:

- `bulbvpn-android.aab` / `bulbvpn-android.apk`
- `bulbvpn-ios.ipa`
- `bulbvpn-macos.zip` when macOS signing is configured
- `bulbvpn-windows.zip` when the script runs on Windows

## App identity

- Bundle / application ID: `app.bulbvpn.com`
- iOS / macOS VPN extension: `app.bulbvpn.com.VPNExtension`
- App group: `group.com.bulbvpn.app`

## Privacy

This is a private build. Ads and paywall seams exist in code but stay off.
You are responsible for how you use the tunnel. BULBVPN is not responsible
for traffic sent through third-party relays.

## Support

Contact: hasanabbassorathiya12@gmail.com

## License

MIT. See [LICENSE](LICENSE).
