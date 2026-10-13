import 'package:flutter/material.dart';

/// BULBVPN "Filament" palette — single accent (Filament Amber), state colors
/// are semantic only. See DESIGN.md §2.
class AppColors {
  // ── Canvas / surfaces ─────────────────────────────────────────────
  static const Color canvas = Color(0xFF0A0D14); // Night Canvas (root bg)
  static const Color surface = Color(0xFF11151F); // Console Surface (sheets, nav)
  static const Color raised = Color(0xFF171C29); // Raised Surface (inputs, chips)

  // ── Text ──────────────────────────────────────────────────────────
  static const Color ink = Color(0xFFF2F4F8); // primary text
  static const Color steel = Color(0xFF99A1B3); // secondary text
  static const Color mute = Color(0xFF5B6478); // tertiary / disabled

  // ── Structure ─────────────────────────────────────────────────────
  static const Color hairline = Color(0x14FFFFFF); // 1px borders (8%)
  static const Color shadow = Color(0x73000000); // sheets (45%)

  // ── Accent (exactly one) ──────────────────────────────────────────
  static const Color amber = Color(0xFFE9A23B); // Filament Amber
  static const Color amberTint = Color(0x1FE9A23B); // ~12% wash

  // ── Semantic status (state reporting only) ────────────────────────
  static const Color emerald = Color(0xFF3FB98A); // connected / download
  static const Color red = Color(0xFFE5484D); // failed / no internet
  static const Color graphite = Color(0xFF3A4152); // idle ring
  static const Color sky = Color(0xFF56A8E8); // upload series

  // ── Legacy aliases (mapped to the new system) ─────────────────────
  static const Color primary = amber;
  static const Color secondary = steel;
  static const Color background = canvas;
  static const Color downloadColor = emerald;
  static const Color uploadColor = sky;
  static const Color warningColor = amber;

  // ── State aura gradients (vertical stack behind the orb) ──────────
  static const Color topGradient = canvas;
  static const Color topGradientReadyToConnect = canvas;
  static const Color topGradientConnecting = canvas;

  // Idle / standby — graphite aura
  static const Color middleGradient = Color(0xFF12151F);
  static const Color bottomGradient = Color(0xFF1C2231);

  // Connected — emerald aura
  static const Color middleGradientConnected = Color(0xFF0F2A23);
  static const Color bottomGradientConnected = Color(0xFF1E5C4B);

  // No internet — deep red aura
  static const Color middleGradientNoInternet = Color(0xFF2E1114);
  static const Color bottomGradientNoInternet = Color(0xFF6B1F2A);

  // Failed to connect — red aura
  static const Color middleGradientFailedToConnect = Color(0xFF2A1216);
  static const Color bottomGradientFailedToConnect = Color(0xFF5C2027);

  // Connecting — warm amber aura
  static const Color middleGradientConnecting = Color(0xFF23190E);
  static const Color bottomGradientConnecting = Color(0xFF6B4A18);

  // ── Speed-test series (semantic) ──────────────────────────────────
  static const Color liveEmerald = emerald;
  static const Color skySeries = sky;
}
