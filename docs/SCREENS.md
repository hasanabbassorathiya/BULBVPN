# Screens

## 1. Home Screen

**File:** `lib/screens/home_screen.dart`

The main landing screen with the hero VPN toggle and quick-access information.

### Layout (Top to Bottom)
1. **Header** — App logo (gradient bolt icon) + "BULB VPN" title + protocol badge
2. **Protected Badge** — Animated pill showing "Protected" (green) or "Unprotected" (gray)
3. **Server Selector** — Tap to change server, shows flag + name + ping
4. **VPN Toggle** — Large 180px circle with pulse animation rings
5. **Status Text** — "Connected • New York" / "Disconnected" / "Connecting..."
6. **Quick Stats Row** — 3 mini cards: Upload speed, Session time, Data used

### Components Used
- `VPNToggle` (animated circle widget)
- `AppColors` gradients and theme
- Custom `_buildMiniStat()` for the stats row

### Animations
- Toggle pulse rings animate when connecting/connected
- Status text color transitions between states
- Protected badge animates color and icon

---

## 2. Servers Screen

**File:** `lib/screens/servers_screen.dart`

Browse, search, and select VPN servers.

### Layout
1. **Header** — "Servers" title
2. **Search Bar** — TextField with search icon
3. **Filter Chips** — Horizontal scroll: All / Americas / Europe / Asia / Low Ping
4. **Best Server Card** — Highlighted recommended server with gradient border
5. **Server List** — Scrollable list of ServerCard widgets

### Components Used
- `ServerCard` (flag, name, ping, load bar, favorite star)
- Filter chip row with animated selection
- Pull-to-refresh (placeholder)

### Server Data
14 servers across 4 regions:
- Americas: US (3), Canada, Brazil
- Europe: UK, Germany, France, Netherlands
- Asia: Japan, Singapore, South Korea, India
- Oceania: Australia

---

## 3. Stats Screen

**File:** `lib/screens/stats_screen.dart`

Real-time connection metrics and session information.

### Layout
1. **Header** — "Statistics" title + subtitle
2. **Speed Cards** — Download (green) + Upload (purple) side by side
3. **Connection Details** — Card with status, server, protocol, IP, connected since
4. **Session Stats** — Duration + Data used side by side

### Components Used
- `StatCard` (icon, label, value, unit, accent color)
- Connection info rows with animated values
- Consumer<VPNProvider> for live data updates

### Metrics Displayed
| Metric | Source | Update Rate |
|--------|--------|-------------|
| Download speed | `vpn.speed.download` | 2 seconds |
| Upload speed | `vpn.speed.upload` | 2 seconds |
| Session time | `vpn.formattedDuration` | 1 second |
| Data used | `vpn.dataUsed` | 1 second |

---

## 4. Settings Screen

**File:** `lib/screens/settings_screen.dart`

App configuration and privacy information.

### Sections

#### Connection
- **Protocol Selector** — Dropdown: WireGuard (default) / OpenVPN
- **Auto-Connect** — Toggle: connect on app start
- **Kill Switch** — Toggle with warning: block internet if VPN drops

#### Appearance
- **Dark Mode** — Toggle (currently dark-only)
- **DNS** — Default (System) navigation tile
- **Notifications** — Connection alerts navigation tile

#### Privacy
- **No-Logs Badge** — Green highlighted card: "We never store or sell your browsing data"
- **Privacy Policy** — Navigation tile
- **About BULB VPN** — Version 1.0.0

### Components Used
- `_buildSection()` — Section container with title
- `_buildSwitchTile()` — Toggle row with icon + title + subtitle
- `_buildNavigationTile()` — Tap row with chevron
- `_buildProtocolSelector()` — Custom dropdown in row
- `_buildNoLogsBadge()` — Highlighted trust signal
