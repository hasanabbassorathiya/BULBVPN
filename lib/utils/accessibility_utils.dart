import 'package:flutter/material.dart';

/// Wrap a widget with Semantics for screen reader support
Widget addSemantics({
  required Widget child,
  required String label,
  String? hint,
  bool isButton = false,
  bool isToggle = false,
  bool? isChecked,
}) {
  return Semantics(
    label: label,
    hint: hint,
    button: isButton,
    toggled: isToggle,
    checked: isChecked,
    child: child,
  );
}

/// Common accessibility labels
class AppAccessibility {
  static const String vpnToggle = 'VPN connection toggle';
  static const String vpnToggleHint = 'Tap to connect or disconnect VPN';
  static const String quickConnect = 'Quick connect to fastest server';
  static const String serverList = 'Server list';
  static const String searchServers = 'Search servers';
  static const String favorites = 'Favorite servers';
  static const String settings = 'Settings';
  static const String profile = 'User profile';
  static const String connectButton = 'Connect to server';
  static const String disconnectButton = 'Disconnect from server';
  static String serverItem(String name, String country, int ping) =>
      '$name, $country, $ping milliseconds';
  static String connectionStatus(bool isConnected) =>
      isConnected ? 'VPN connected' : 'VPN disconnected';
  static String protectionStatus(bool isProtected) =>
      isProtected ? 'Protected' : 'Unprotected';
}
