# BULB VPN OpenVPN Integration Plan

> **For agentic workers:** Execute this plan task-by-task.

**Goal:** Replace WireGuard with OpenVPN, fetch 100+ servers from VPN Gate API, and create a production-quality VPN app with elegant UI.

**Architecture:** Flutter app with OpenVPN via platform channels, VPN Gate API for server list, and a premium dark-mode UI with real-time stats.

**Tech Stack:** Flutter, OpenVPN (Android VpnService), VPN Gate API, Provider state management

---

### Task 1: Add OpenVPN dependency and server API

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/models/vpn_server.dart` (update)
- Create: `lib/services/vpn_gate_api.dart`
- Create: `lib/services/open_vpn_service.dart`

### Task 2: Native OpenVPN Android integration

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/main/kotlin/app/bulbvpn/com/OpenVpnManager.kt`
- Modify: `android/app/src/main/kotlin/app/bulbvpn/com/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

### Task 3: Update Flutter VPN service layer

**Files:**
- Modify: `lib/services/wireguard_service.dart` → rename to `lib/services/vpn_service.dart`
- Modify: `lib/providers/vpn_provider.dart`

### Task 4: Overhaul UI for elegance

**Files:**
- Modify: All screen files
- Modify: `lib/constants/app_theme.dart`

### Task 5: Test and build

- [ ] Run flutter analyze
- [ ] Build APK
- [ ] Test on device
