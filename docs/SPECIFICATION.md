# Specification

## High-Level Purpose

BULB VPN is a minimal, trustworthy, and lightning-fast VPN that makes secure browsing effortless. It prioritizes clarity, delight, and performance with bold visuals, smooth interactions, and essential features only. The app feels premium, playful yet professional, modern, and reliable.

## Core Functionality

- One-tap connect/disconnect with real-time status
- Smart server selection with ping/load indicators
- Live stats dashboard for transparency
- Essential privacy controls (protocol, kill switch, auto-connect)
- Lightweight, battery-efficient, with quick reconnection
- Supports WireGuard (default) and OpenVPN protocols
- No-logs policy (highlighted in UI)
- Cross-platform ready (mobile-first design)

## User Flows

### 1. Home Screen (Launch/Default)
- Hero element: Large, satisfying circular toggle (connect/disconnect) in the center
- Status text: "Connected • US-East" or "Disconnected" with subtle animation
- Current server flag + location
- Quick stats row: Speed (up/down), Session Time, Data Used
- Bottom floating navbar for navigation (Home, Servers, Stats, Settings)
- Background: Subtle gradient with connection "pulse" effect when active
- Trust signals: Security lock icon, "Protected" badge

### 2. Server Selection Screen
- Clean vertical list of locations
- Each card shows: Flag, City/Country, Ping (ms with color), Load % (bar), Favorite star
- Search bar at top
- Recommended "Best" server highlighted
- Pull-to-refresh for updated ping data
- Fast filter: All / Americas / Europe / Asia / Low Ping

### 3. Stats Screen
- Big, bold, readable numbers with large typography
- Cards/metrics:
  - Download/Upload speed (real-time gauges)
  - Total data used (this session / today)
  - Session duration
  - Server IP, Protocol, Connected Since
- Export/share log option

### 4. Settings Screen
- Minimal list:
  - Protocol (WireGuard / OpenVPN)
  - Auto-connect on Wi-Fi / always
  - Kill Switch (toggle with warning)
  - App Theme (Light / Dark / System)
  - DNS (default / custom)
  - Notifications
  - About / Privacy Policy / No-logs badge
- Simple, spaced layout

## Aesthetic & Style Guide

### Overall Vibe
Playful yet premium, energetic, trustworthy. Vibrant accents on clean dark/light backgrounds. Modern, rounded, generous spacing, high contrast.

### Color Palette
| Color | Hex | Usage |
|-------|-----|-------|
| Primary accent | #00E5C0 | Toggles, active states, progress |
| Secondary | #9B59B6 | Purple gradients, backgrounds |
| Accent | #6C63FF | Secondary highlights |
| Base dark | #0A0F1C | Background |
| Surface | #111827 | Cards, surfaces |
| Card | #1A2332 | Card backgrounds |
| Connected | #00E5C0 | Active/connected state |
| Disconnected | #EF4444 | Error/disconnected state |
| Warning | #FBBF24 | Caution states |

### Typography
- Bold, large display fonts for hero numbers, status, and metrics
- Clean, highly legible body text with excellent hierarchy
- Ample line height and letter spacing
- Font: Inter (Google Fonts)

### UI Elements
- Rounded corners (16-20px radius) on cards, buttons, toggle
- Floating bottom navbar with icons
- Generous padding, rhythmic vertical spacing
- Hero toggle: Large circular with inner glow/pulse when connecting
- Cards with soft shadows, subtle borders or glassmorphic effects
- Toggle switches: Custom, large, colorful
- List items: Flag emoji + text + right-aligned metrics
