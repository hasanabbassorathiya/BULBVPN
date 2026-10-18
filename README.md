# BULBVPN

Private VPN client for Android, iOS, macOS, and Windows. Built with Flutter.
It dials OpenVPN first on Iranian Wi‑Fi and mobile data, keeps a live tunnel
across network changes, and falls back to SoftEther on Android when needed.

## Features

- One-tap connect and disconnect
- Device-side server ping with the fastest relay on top
- OpenVPN-first connect that prefers the relay’s own port
- Session restore when you reopen the app while the tunnel is still up
- Built-in Cloudflare speed test
- Private UI: country labels only, no public relay hostnames in the home screen
- SoftEther SSL-VPN path on Android as a short fallback

## Platforms

| Platform | Status |
| --- | --- |
| Android | Production path verified on Iranian Wi‑Fi and mobile data |
| iOS | Packet tunnel + App Store upload |
| macOS | Packet tunnel provider (OpenVPNAdapter) |
| Windows | Bundled OpenVPN + TAP; run the release script on Windows |

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
