# Theme

## Color Palette

### Primary Colors
| Name | Hex | Usage |
|------|-----|-------|
| Primary | `#00E5C0` | Toggles, active states, progress bars, connected state |
| Primary Dark | `#00B89C` | Gradient endpoint |
| Secondary | `#9B59B6` | Purple gradient, upload speed |
| Accent | `#6C63FF` | Secondary highlights, session stats |

### Background Colors
| Name | Hex | Usage |
|------|-----|-------|
| Bg Dark | `#0A0F1C` | Main background |
| Bg Surface | `#111827` | Cards, surfaces |
| Bg Card | `#1A2332` | Card backgrounds |
| Bg Card Light | `#1F2D3D` | Borders, subtle elements |

### Text Colors
| Name | Hex | Usage |
|------|-----|-------|
| Text Primary | `#FFFFFF` | Headings, primary text |
| Text Secondary | `#94A3B8` | Descriptions, labels |
| Text Muted | `#64748B` | Disabled, hints |

### Status Colors
| Name | Hex | Usage |
|------|-----|-------|
| Connected | `#00E5C0` | Active VPN, protected badge |
| Disconnected | `#EF4444` | Error, unprotected |
| Warning | `#FBBF24` | Caution, favorites |

### Ping Colors
| Range | Hex | Label |
|-------|-----|-------|
| < 50ms | `#00E5C0` | Excellent |
| 50-99ms | `#34D399` | Good |
| 100-149ms | `#FBBF24` | Fair |
| 150+ms | `#EF4444` | Poor |

## Gradients

### Background Gradient
```dart
LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0F172A), Color(0xFF0A0F1C)]
)
```

### Hero Gradient (logo, chips)
```dart
LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6C63FF), Color(0xFF00E5C0)]
)
```

### Connected Gradient (toggle when active)
```dart
LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00E5C0), Color(0xFF00B89C)]
)
```

### Card Gradient
```dart
LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1A2332), Color(0xFF111827)]
)
```

## Typography

**Font Family:** Inter (via Google Fonts)

| Element | Size | Weight | Color |
|---------|------|--------|-------|
| Screen Title | 26px | w800 | White |
| App Title | 20px | w800 | White (tracked) |
| Server Name | 16px | w600 | White / Primary |
| Status Text | 16px | w600 | Dynamic |
| Body | 15px | w600 | White |
| Label | 14px | w500 | Secondary |
| Small | 13px | w600 | Primary / Secondary |
| Micro | 12px | w500 | Muted / Secondary |
| Badge | 9px | w700 | White |

## Border Radius

| Element | Radius |
|---------|--------|
| Cards | 16-20px |
| Toggle | 50% (circle) |
| Buttons/Pills | 20-24px |
| Stat Cards | 16px |
| Input Fields | 14px |
| Icons | 10px |

## Navigation Bar

- **Position:** Floating, 24px margin from edges, 28px from bottom
- **Shape:** Pill (24px radius)
- **Background:** Surface color at 95% opacity
- **Border:** White at 6% opacity
- **Active State:** Teal background (15% opacity) + teal icon/label
- **Inactive State:** Gray icon, no background
