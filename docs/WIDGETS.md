# Widgets

## VPNToggle

**File:** `lib/widgets/vpn_toggle.dart`

The hero connect/disconnect button with animated pulse rings.

### Properties
None (reads state from VPNProvider via Consumer)

### Behavior
- **Idle:** Dark circle with power icon (gray)
- **Connecting:** Spinner inside, expanding pulse rings (fading teal)
- **Connected:** Green gradient circle with shield icon, glowing shadow, pulsing rings
- **Tap:** Scales down to 0.95 then bounces back (elastic animation)

### Animations
- `_pulseController` — 1500ms repeat pulse for connection rings
- `_scaleController` — 200ms elastic bounce on tap

---

## ServerCard

**File:** `lib/widgets/server_card.dart`

Individual server list item with flag, details, and metrics.

### Properties
| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `server` | `VPNServer` | Yes | Server data |
| `isSelected` | `bool` | No | Highlight if this is the active server |
| `onTap` | `VoidCallback` | Yes | Tap handler |
| `onFavorite` | `VoidCallback?` | No | Star toggle handler |

### Layout
```
[Flag 32px] [Name + Country]  [Ping dot + ms]
            [PRO badge]       [Load bar + %]
                              [Star icon]
```

### Ping Color Logic
| Ping | Color | Label |
|------|-------|-------|
| < 50ms | #00E5C0 (teal) | Excellent |
| 50-99ms | #34D399 (green) | Good |
| 100-149ms | #FBBF24 (yellow) | Fair |
| 150+ms | #EF4444 (red) | Poor |

---

## StatCard

**File:** `lib/widgets/stat_card.dart`

Metric display card with icon, label, and large value.

### Properties
| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `icon` | `IconData` | Yes | Card icon |
| `label` | `String` | Yes | Metric name |
| `value` | `String` | Yes | Metric value |
| `unit` | `String` | No | Unit suffix (e.g. "Mbps") |
| `accentColor` | `Color?` | No | Custom accent (defaults to primary) |

### Layout
```
[Icon in tinted box] [Label]
[     Large Value    ] [Unit]
```

---

## GlassmorphicCard

**File:** `lib/widgets/glassmorphic_card.dart`

Frosted glass effect container using BackdropFilter.

### Properties
| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `child` | `Widget` | Yes | Content |
| `borderRadius` | `double` | No | Corner radius (default: 20) |
| `padding` | `EdgeInsetsGeometry?` | No | Inner padding |
| `margin` | `EdgeInsetsGeometry?` | No | Outer margin |

### Effect
- 20px Gaussian blur on background
- Semi-transparent white gradient (8% → 2%)
- Subtle white border (10% opacity)
