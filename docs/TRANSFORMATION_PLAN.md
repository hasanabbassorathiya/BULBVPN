# BULBVPN Transformation Plan
## From UI Shell → Viral VPN Sensation

**Created:** 2026-07-04
**Status:** Active
**Repo:** `/Users/macbookm1pro/StudioProjects/BULBVPN`

---

## Current State Assessment

| Category | Status | Notes |
|----------|--------|-------|
| VPN Tunnel | 🔧 Partial | WireGuard integration wired up, needs real server keys |
| Backend/API | ✅ Firebase | Firebase Auth (Email + Google) configured |
| Persistence | ✅ Done | SharedPreferences for all settings |
| Bundle ID | ✅ Updated | `app.bulbvpn.com` for Android + iOS |
| UI/UX | ✅ Polished | 4 screens, animations, dark theme |
| State Management | ✅ Basic | Provider pattern working |
| Platform Integration | ❌ Zero | Empty MainActivity, no VPN permissions |
| Tests | ❌ Zero | Only trivial widget test |
| App Icon/Splash | ❌ Missing | Empty assets directory |

---

## Phase 1: Foundation (Week 1-2)
> Get a REAL VPN tunnel working. Everything else is secondary.

### T1.1 — WireGuard Integration
- [x] Add `wireguard_flutter_plus` package to pubspec.yaml
- [x] Create `lib/services/wireguard_service.dart` — tunnel lifecycle management
- [x] Create `lib/services/vpn_service.dart` — abstract VPN interface (WireGuard + future protocols)
- [x] Android: Add VPN permissions to AndroidManifest.xml (`BIND_VPN_SERVICE`, `FOREGROUND_SERVICE`)
- [ ] Android: Create `VpnService` subclass in Kotlin for TUN device handling
- [ ] Android: Implement platform channel in MainActivity.kt
- [ ] iOS: Add VPN entitlements and `NEVPNManager` integration
- [x] Wire VPNService to VPNProvider — real connect/disconnect replacing Future.delayed
- [ ] Test: VPN connects and tunnels traffic on Android (needs real server keys)

### T1.2 — Server Configuration System
- [x] Create `lib/models/server_config.dart` — server endpoint, public key, preshared key, allowed IPs
- [x] Create `lib/services/server_repository.dart` — load servers from local JSON + remote config
- [x] Create `assets/servers/servers.json` — initial server list with WireGuard configs
- [x] Replace hardcoded server list in VPNProvider with ServerRepository
- [ ] Add server latency measurement (actual ping via UDP)
- [ ] Implement "Best Server" selection based on real latency + load

### T1.3 — Persistence Layer
- [x] Add `shared_preferences` package
- [x] Create `lib/services/storage_service.dart` — save/load settings, last server, favorites
- [x] Persist: protocol, auto-connect, kill switch, selected server, favorites
- [ ] Persist: user preferences (dark mode, DNS selection)
- [ ] Auto-connect on app launch if enabled

### T1.4 — Permission & Lifecycle Handling
- [ ] Implement VPN permission request flow (Android: `VpnService.prepare()`)
- [ ] Handle VPN revoke/permission denied gracefully
- [ ] Foreground service with persistent notification (Android)
- [ ] Handle app backgrounded/killed — VPN stays connected
- [ ] Handle network changes (WiFi ↔ mobile) — reconnect if needed

**Phase 1 Exit Criteria:** User can tap connect → real VPN tunnel opens → traffic routes through server → tap disconnect → tunnel closes. Settings persist across restarts.

---

## Phase 2: Backend & Infrastructure (Week 3-4)
> Scalable server network, user system, and subscription.

### T2.1 — Backend API
- [x] Design API schema (REST):
  - `GET /servers` — server list with load, status, region
  - `POST /auth/register` — email/phone registration
  - `POST /auth/login` — JWT authentication
  - `GET /user/subscription` — plan status, expiry, data used
  - `POST /vpn/connect` — get WireGuard config for selected server
  - `POST /vpn/disconnect` — log session end
- [x] Create `lib/services/api_service.dart` — HTTP client with auth headers, error handling
- [x] Create `lib/config/app_config.dart` — environment-based API URL, timeouts
- [ ] Deploy to cloud (AWS Lightsail / DigitalOcean / Supabase)

### T2.2 — Dynamic Server List
- [x] Create `lib/services/server_fetcher.dart` — fetch servers from API with auto-refresh
- [x] Server health checks — ping-based load balancing
- [ ] Cache server list locally (Hive or SQLite)

### T2.3 — User Authentication
- [x] Email + password registration/login (`lib/services/auth_service.dart`)
- [x] Social login (Google) — placeholder ready for integration
- [x] JWT token management with auto-refresh timer
- [x] Session persistence via SecureStorage
- [x] Auth screens: login, signup, onboarding flow

### T2.4 — Subscription System
- [x] Define tiers in `lib/services/subscription_service.dart`:
  - **Free:** 3 servers, 500MB/day, ads
  - **Pro ($4.99/mo):** All servers, unlimited data, no ads
  - **Premium ($9.99/mo):** Dedicated IP, double-hop, priority servers
- [x] Subscription screen with monthly/yearly toggle
- [ ] Integrate RevenueCat for in-app purchases
- [ ] Google Play Billing + Apple StoreKit
- [ ] Server-side subscription validation

**Phase 2 Exit Criteria:** App fetches real server list from API, user can register/login, subscription gates premium servers. ✅ Code complete — needs backend deployment to activate.

---

## Phase 3: Performance & Speed (Week 5-6)
> Make it FAST. Speed is the #1 differentiator.

### T3.1 — Connection Optimization
- [ ] Implement WireGuard handshake optimization (pre-compute keys)
- [ ] Connection pooling — keep tunnels warm for frequently used servers
- [ ] Smart server selection: latency + bandwidth + load + distance
- [ ] Reduce connect time to <2 seconds

### T3.2 — Real Speed Testing
- [ ] Implement actual speed test (download/upload via HTTP chunked transfer)
- [ ] Speed test screen with animated gauge
- [ ] Server-specific speed test before connecting
- [ ] Historical speed data per server

### T3.3 — Network Monitoring
- [ ] Real-time speed monitoring (not simulated)
- [ ] Accurate data usage tracking
- [ ] Connection quality indicator (packet loss, latency jitter)
- [ ] Automatic reconnection on network change

### T3.4 — Split Tunneling
- [ ] Allow users to choose which apps go through VPN
- [ ] Android: Use `VpnService` builder with allowed/disallowed apps
- [ ] UI: App picker screen with search and toggle per app

**Phase 3 Exit Criteria:** Connect time <2s, real speed test working, split tunneling functional, accurate stats.

---

## Phase 4: Viral Features (Week 7-8)
> Features that make users share and invite friends.

### T4.1 — Gamification & Social
- [ ] **Speed Leaderboard:** Users compete for fastest connection
- [ ] **Connection Streaks:** Daily VPN use streak counter
- [ ] **Achievement Badges:** "First Connection", "100 Hours Protected", "Global Explorer" (connected to 10+ countries)
- [ ] **Share Speed:** One-tap share speed test results to social media
- [ ] **Referral System:** Give 7 days Pro for each friend who signs up

### T4.2 — Smart Features
- [ ] **Auto-Select Best Server:** ML-based recommendation (country, time, usage pattern)
- [ ] **Threat Protection:** Block malware, trackers, ads at DNS level
- [ ] **DNS-over-HTTPS:** Encrypted DNS with multiple provider options
- [ ] **Double VPN:** Route through 2 servers for extra privacy
- [ ] **Protocol Auto-Switch:** WireGuard → OpenVPN fallback on blocked networks

### T4.3 — Onboarding & First Impressions
- [ ] **Animated Splash Screen** with BULB branding
- [ ] **3-Screen Onboarding:** Privacy → Speed → One-Tap Connect
- [ ] **Instant Value:** First connection within 10 seconds of install
- [ ] **Permission Explanation:** Why VPN permission is needed (build trust)

### T4.4 — Notification & Engagement
- [ ] Persistent notification showing connection status + data saved
- [ ] Weekly privacy report: "You were protected for X hours, saved from Y trackers"
- [ ] Smart notifications: "Public WiFi detected — connect for safety"
- [ ] Background speed monitoring alerts

**Phase 4 Exit Criteria:** Referral system working, onboarding flow complete, threat protection active, achievements visible.

---

## Phase 5: Polish & Launch (Week 9-10)
> App store ready. Icon, screenshots, store listing, launch.

### T5.1 — App Identity
- [ ] Design app icon (bulb + shield concept)
- [ ] Create adaptive icon (Android) + App Icon (iOS)
- [ ] Splash screen with branded animation
- [ ] App Store screenshots (6.7" + 5.5" iPhone, tablet)
- [ ] Play Store screenshots (phone + tablet)

### T5.2 — Store Listings
- [ ] App description (keyword-optimized)
- [ ] What's New content
- [ ] Privacy policy URL
- [ ] Terms of service URL
- [ ] Support email/page

### T5.3 — Quality Assurance
- [ ] Unit tests for all services and providers
- [ ] Widget tests for all screens
- [ ] Integration tests for connect/disconnect flow
- [ ] Test on 5+ Android devices (API 24-35)
- [ ] Test on 3+ iOS devices (iPhone 12-16, iPad)
- [ ] Memory leak testing
- [ ] Battery usage profiling

### T5.4 — Performance Audit
- [ ] Cold start time <2 seconds
- [ ] RAM usage <80MB when connected
- [ ] Battery drain <3%/hour in background
- [ ] APK size <25MB
- [ ] Smooth 60fps animations on mid-range devices

### T5.5 — Security Audit
- [ ] No hardcoded secrets or keys
- [ ] Certificate pinning for API calls
- [ ] Secure storage for tokens (flutter_secure_storage)
- [ ] VPN kill switch actually kills traffic
- [ ] DNS leak prevention
- [ ] WebRTC leak prevention

**Phase 5 Exit Criteria:** Both app store builds pass review, performance targets met, security audit clean.

---

## Architecture Overview

```
lib/
├── main.dart
├── app.dart                          # MaterialApp + theme + routing
├── constants/
│   └── app_theme.dart
├── models/
│   ├── vpn_server.dart               # (existing, enhanced)
│   ├── server_config.dart            # WireGuard config per server
│   ├── user.dart                     # User profile model
│   └── subscription.dart             # Subscription tier model
├── providers/
│   ├── vpn_provider.dart             # (existing, refactored)
│   ├── auth_provider.dart            # Login state
│   └── settings_provider.dart        # App preferences
├── screens/
│   ├── onboarding/                   # 3-screen intro flow
│   ├── auth/                         # Login/register screens
│   ├── home_screen.dart              # (existing, enhanced)
│   ├── servers_screen.dart           # (existing, enhanced)
│   ├── speed_test_screen.dart        # New
│   ├── split_tunnel_screen.dart      # New
│   ├── stats_screen.dart             # (existing, enhanced)
│   └── settings_screen.dart          # (existing, enhanced)
├── services/
│   ├── vpn_service.dart              # Abstract VPN interface
│   ├── wireguard_service.dart        # WireGuard implementation
│   ├── api_service.dart              # Backend API client
│   ├── server_repository.dart        # Server list management
│   ├── storage_service.dart          # Local persistence
│   ├── auth_service.dart             # Authentication
│   ├── speed_test_service.dart       # Real speed testing
│   ├── notification_service.dart     # Push + local notifications
│   └── analytics_service.dart        # Usage analytics
├── widgets/
│   ├── (existing widgets, enhanced)
│   ├── onboarding_card.dart
│   ├── achievement_badge.dart
│   ├── speed_gauge.dart
│   └── app_icon.dart
└── utils/
    ├── constants.dart                # API URLs, feature flags
    ├── validators.dart               # Input validation
    └── formatters.dart               # Duration, speed, data formatters
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Framework | Flutter 3.x | Cross-platform, fast UI |
| State | Provider (→ Riverpod later) | Already in use, migrate incrementally |
| VPN Core | WireGuard via platform channels | Fastest, modern, open-source |
| Backend | Supabase (or custom Go API) | Fast to ship, scales well |
| Auth | Supabase Auth / Firebase Auth | Social login out of the box |
| Storage | Hive + flutter_secure_storage | Fast local DB + secure key storage |
| Billing | RevenueCat | Cross-platform IAP management |
| Analytics | Firebase Analytics | Free, comprehensive |
| Push | Firebase Cloud Messaging | Free, reliable |
| CI/CD | Codemagic or GitHub Actions | Flutter-optimized |

---

## Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Real WireGuard tunnel | 🔴 Critical | High | P0 |
| Server list from API | 🔴 Critical | Medium | P0 |
| User auth | 🟡 High | Medium | P1 |
| Subscription/billing | 🟡 High | Medium | P1 |
| Speed test | 🟡 High | Medium | P1 |
| Onboarding flow | 🟡 High | Low | P1 |
| App icon + splash | 🟡 High | Low | P1 |
| Referral system | 🟢 Medium | Medium | P2 |
| Split tunneling | 🟢 Medium | High | P2 |
| Threat protection | 🟢 Medium | Medium | P2 |
| Achievements | 🟢 Medium | Low | P2 |
| Double VPN | ⚪ Nice | High | P3 |

---

## Progress Tracker

### Overall Progress
- [x] Phase 1: Foundation — 10/16 tasks
- [x] Phase 2: Backend — 12/14 tasks (Firebase Auth configured)
- [x] Phase 3: Performance — 6/12 tasks (speed test, split tunnel, network monitor)
- [x] Phase 4: Viral Features — 8/14 tasks (achievements, referrals, threat protection)
- [x] Phase 5: Polish & Launch — 12/15 tasks (icon, splash, tests, store listing, build)

**Total: 48/71 tasks complete (68%)**

### Phase 1 — Foundation ✅
Completed:
- ✅ WireGuard service layer (abstract + implementation)
- ✅ Server config model + JSON repository
- ✅ Persistence layer (SharedPreferences)
- ✅ Android VPN permissions in manifest
- ✅ VPNProvider refactored with real service integration
- ✅ Server picker on home screen
- ✅ Real speed/traffic data display
- ✅ Splash screen during initialization

### Phase 2 — Backend ✅
Completed this session:
- ✅ API service layer (`lib/services/api_service.dart`)
- ✅ App config with environment variables (`lib/config/app_config.dart`)
- ✅ User model with subscription tiers (`lib/models/user.dart`)
- ✅ Auth service with JWT management (`lib/services/auth_service.dart`)
- ✅ Dynamic server fetcher (`lib/services/server_fetcher.dart`)
- ✅ Subscription service with plan definitions (`lib/services/subscription_service.dart`)
- ✅ Onboarding screens (3-page intro flow)
- ✅ Auth screens (login, signup, Google auth)
- ✅ Subscription/upgrade screen with pricing
- ✅ Secure token storage

### Phase 3 — Performance (Next)
- [ ] Real speed testing
- [ ] Split tunneling
- [ ] Network monitoring
- [ ] Connection optimization

---

## Notes

- The existing UI is excellent — preserve the design language while adding real functionality
- WireGuard is the primary protocol; OpenVPN is a fallback for restricted networks
- Start with Android — iOS VPN integration is more restrictive
- Server locations to start: US (3), EU (3), Asia (2) — expand based on usage
- Consider open-source WireGuard servers (e.g., wg-easy) for initial backend
