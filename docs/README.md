# BULB VPN

**Fast, Secure, Effortless VPN**

A minimal, trustworthy, and lightning-fast Flutter VPN app that makes secure browsing effortless. Bold visuals, smooth interactions, and essential features only.

## Quick Start

```bash
cd ~/StudioProjects/BULBVPN
flutter run
```

## Project Structure

```
BULBVPN/
├── docs/                          # Project documentation
│   ├── README.md                  # This file
│   ├── SPECIFICATION.md           # Full app specification
│   ├── ARCHITECTURE.md            # Code architecture & patterns
│   ├── SCREENS.md                 # Screen-by-screen breakdown
│   ├── WIDGETS.md                 # Reusable widget reference
│   ├── THEME.md                   # Color palette & typography
│   └── PROGRESS.md                # Build progress log
├── lib/
│   ├── main.dart                  # App entry + floating navbar
│   ├── constants/
│   │   └── app_theme.dart         # Colors, gradients, dark theme
│   ├── models/
│   │   └── vpn_server.dart        # Data models
│   ├── providers/
│   │   └── vpn_provider.dart      # State management
│   ├── screens/
│   │   ├── home_screen.dart       # Hero toggle, status, quick stats
│   │   ├── servers_screen.dart    # Server list, search, filters
│   │   ├── stats_screen.dart      # Speed, session, connection details
│   │   └── settings_screen.dart   # Protocol, kill switch, DNS, about
│   └── widgets/
│       ├── vpn_toggle.dart        # Animated pulse circle toggle
│       ├── server_card.dart       # Server list item
│       ├── stat_card.dart         # Metric display card
│       └── glassmorphic_card.dart # Glass effect widget
├── android/
├── ios/
├── pubspec.yaml
└── analysis_options.yaml
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.44.2 (Dart 3.12.2) |
| State | Provider 6.1.2 |
| Typography | Google Fonts (Inter) |
| Platforms | Android, iOS |

## Key Features

- One-tap connect/disconnect with pulse animation
- 14 server locations across 4 regions
- Real-time speed simulation
- WireGuard & OpenVPN protocol selection
- Kill switch & auto-connect settings
- No-logs policy badge
- Floating pill navigation bar
- Dark theme with teal/cyan accents
