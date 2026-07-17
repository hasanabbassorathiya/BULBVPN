# Architecture

## Overview

BULB VPN uses a clean, straightforward Flutter architecture with Provider for state management. The app follows a simple screen-based structure without complex routing.

## Pattern: Screen + Provider

```
Screen (StatelessWidget)
  └─ Consumer<VPNProvider>  ← watches state
       └─ UI widgets        ← render based on state
```

## State Management

### VPNProvider (ChangeNotifier)
Single source of truth for all app state. Manages:

| State | Type | Description |
|-------|------|-------------|
| `status` | `VPNStatus` | disconnected / connecting / connected / disconnecting |
| `selectedServer` | `VPNServer?` | Currently chosen server |
| `connection` | `VPNConnection` | Active connection metadata |
| `speed` | `SpeedData` | Current download/upload speeds |
| `servers` | `List<VPNServer>` | All available servers |
| `serverFilter` | `ServerFilter` | Active filter category |
| `searchQuery` | `String` | Server search text |
| `protocol` | `String` | WireGuard or OpenVPN |
| `autoConnect` | `bool` | Auto-connect preference |
| `killSwitch` | `bool` | Kill switch preference |
| `darkMode` | `bool` | Theme preference |

### Connection Flow
```
User taps toggle
  → toggleConnection()
    → if disconnected: connect()
      → status = connecting
      → delay 1.8s (simulated handshake)
      → status = connected
      → start speed simulation (2s interval)
      → start duration timer (1s interval)
    → if connected: disconnect()
      → status = disconnecting
      → stop timers
      → delay 0.8s
      → status = disconnected
      → reset speed/connection
```

## Data Models

### VPNServer
```dart
class VPNServer {
  final String id;          // e.g. 'us-1'
  final String name;        // e.g. 'New York'
  final String country;     // e.g. 'United States'
  final String countryCode; // e.g. 'US'
  final String flag;        // e.g. '🇺🇸'
  final int ping;           // ms
  final double load;        // percentage 0-100
  final bool isPremium;     // requires Pro
  final bool isFavorite;    // user favorited
}
```

### VPNConnection
```dart
class VPNConnection {
  final String? serverId;
  final DateTime? connectedAt;
  final int durationSeconds;
  final double dataUsedMB;
}
```

### SpeedData
```dart
class SpeedData {
  final double download; // Mbps
  final double upload;   // Mbps
}
```

## File Organization

| Directory | Purpose |
|-----------|---------|
| `lib/constants/` | Theme colors, gradients, text styles |
| `lib/models/` | Data classes (VPNServer, VPNConnection, etc.) |
| `lib/providers/` | State management (VPNProvider) |
| `lib/screens/` | Full-screen pages (Home, Servers, Stats, Settings) |
| `lib/widgets/` | Reusable UI components |

## Navigation

Uses `NavigationBar` with `IndexedStack`-style switching via `AnimatedSwitcher`. The floating bottom bar is a custom widget with pill-shaped active states.

```
MainNavigation (StatefulWidget)
  ├─ index 0: HomeScreen
  ├─ index 1: ServersScreen
  ├─ index 2: StatsScreen
  └─ index 3: SettingsScreen
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | ^6.1.2 | State management |
| `google_fonts` | ^6.2.1 | Inter font family |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
