# BULB VPN

A modern, secure VPN application built with Flutter that provides internet freedom and privacy protection.

![BULB VPN](docs/screenshot-home.png)

## Features

### Core VPN
- **One-tap connection** — Connect to a secure server instantly
- **OpenVPN protocol** — Industry-standard encryption
- **Global server network** — Servers in 50+ countries via VPN Gate
- **Smart server selection** — Auto-selects the fastest server based on ping and load
- **Kill Switch** — Blocks internet if VPN drops unexpectedly
- **Auto-reconnect** — Automatically reconnects after unexpected disconnections
- **Split Tunneling** — Choose which apps bypass the VPN

### Server Experience
- **Country-grouped server browser** with expandable sections
- **Category tabs** — All, Favorites, Recommended, Streaming, Gaming
- **Search with debounce** — Find servers by name or country
- **Server scoring** — Latency, load, and premium status weighted ranking
- **Server detail sheet** — Long-press for full server info

### Premium UI
- **Dark/Light themes** with semantic color system
- **Animated VPN toggle** with glow effects and connection stages
- **Speed test** with Ookla-style gauge UI
- **Connection history** with persistence
- **Responsive layouts** — Phone, tablet, desktop
- **Localization** — English, Spanish, Portuguese
- **Accessibility** — Semantics labels, screen reader support

### Monetization (Stubbed)
- **RevenueCat** integration (pending native SDK)
- **AdMob** integration (pending Gradle 9.x compat)
- **Paywall** with feature comparison
- **Free tier** enforcement (3 servers, 500MB/day, 1hr session)

### Analytics & Monitoring
- **Firebase Analytics** — Event tracking across all screens
- **Firebase Crashlytics** — Error reporting
- **FCM** — Push notification architecture

## Architecture

```
lib/
├── config/          # App configuration
├── constants/       # Theme, colors, typography (AppSemanticColors)
├── l10n/            # Localization (EN/ES/PT)
├── models/          # Data models (VpnServer, User, ConnectionRecord, etc.)
├── providers/       # State management (VPNProvider, AuthProvider, etc.)
├── screens/         # 15 screens (home, servers, stats, settings, etc.)
├── services/        # 18 services (VPN, API, analytics, storage, etc.)
├── utils/           # Utilities (accessibility, app utils)
└── widgets/         # 15 reusable widgets + 7 design system components
```

## Getting Started

### Prerequisites
- Flutter SDK 3.12+
- Android Studio / Xcode
- Firebase project configured

### Setup
```bash
# Clone the repository
git clone https://github.com/hasanabbassorathiya/BULBVPN.git
cd BULBVPN

# Install dependencies
flutter pub get

# Run on emulator
flutter run
```

### Build
```bash
# Android Debug
flutter build apk --debug

# Android Release
flutter build apk --release
```

## Firebase Setup

1. Create a Firebase project
2. Run `flutterfire configure`
3. Enable Authentication (Email/Google)
4. Enable Analytics and Crashlytics
5. Configure App Distribution for testing

## Tech Stack

| Technology | Purpose |
|------------|---------|
| Flutter 3.12+ | Cross-platform UI |
| axevpn_flutter | VPN engine (OpenVPN/WireGuard) |
| Provider | State management |
| Firebase Core | Backend services |
| Firebase Auth | Authentication |
| Firebase Analytics | Event tracking |
| Firebase Crashlytics | Error reporting |
| RevenueCat | Subscriptions (stubbed) |
| Google Mobile Ads | Ad monetization (stubbed) |
| SharedPreferences | Local storage |
| HTTP | Network requests |

## Project Structure

- **15 screens** — Home, Servers, Stats, Settings, Onboarding, Auth, Profile, Paywall, Speed Test, About, Contact, Split Tunneling, Threat Protection, Diagnostics, History
- **18 services** — VPN, API, Auth, Analytics, Crashlytics, Storage, Notifications, etc.
- **4 providers** — VPN, Auth, Ad, Subscription
- **6 models** — VpnServer, User, ConnectionRecord, InAppMessage, ServerConfig, VPNStatus
- **15 widgets** — VPN toggle, server card, stat card, promo banner, etc.
- **7 design system components** — AppCard, AppButton, AppBadge, AppShimmer, SpeedGauge, AppBottomSheet, AppTextField
- **3 languages** — English, Spanish, Portuguese

## License

Private - All rights reserved.
