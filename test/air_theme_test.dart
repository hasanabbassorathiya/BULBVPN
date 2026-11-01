import 'dart:math' as math;

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void _expectAA(AirColors c, Color fg, Color bg, String why) {
  expect(
    contrast(fg, bg),
    greaterThanOrEqualTo(4.5),
    reason: '${c.brightness.name}: $why',
  );
}

void main() {
  test('Clear Air text pairs meet WCAG AA', () {
    const c = AirColors.day;
    _expectAA(c, c.ink, c.ground, 'ink on ground');
    _expectAA(c, c.ink, c.surface, 'ink on surface');
    _expectAA(c, c.steel, c.ground, 'steel on ground');
    _expectAA(c, c.steel, c.surface, 'steel on surface');
    _expectAA(c, c.accentInk, c.ground, 'accent text on ground');
    _expectAA(c, c.connectedInk, c.surface, 'connected text on surface');
    _expectAA(c, c.alertInk, c.ground, 'alert text on ground');
    _expectAA(c, c.accentInk, c.accentWash, 'selected row');
    _expectAA(c, c.alertInk, c.accentWash, 'warning on wash');
  });

  test('Night Air text pairs meet WCAG AA', () {
    const c = AirColors.night;
    _expectAA(c, c.ink, c.ground, 'ink on ground');
    _expectAA(c, c.ink, c.surface, 'ink on surface');
    _expectAA(c, c.steel, c.ground, 'steel on ground');
    _expectAA(c, c.steel, c.surface, 'steel on surface');
    _expectAA(c, c.accentInk, c.ground, 'accent text on ground');
    _expectAA(c, c.connectedInk, c.surface, 'connected text on surface');
    _expectAA(c, c.alertInk, c.ground, 'alert text on ground');
    _expectAA(c, c.accentInk, c.accentWash, 'selected row');
    _expectAA(c, c.alertInk, c.accentWash, 'warning on wash');
  });

  test('the two worlds stay distinct', () {
    expect(AirColors.day.ground, isNot(AirColors.night.ground));
    expect(AirColors.day.ink, isNot(AirColors.night.ink));
    expect(AirColors.day.brightness, Brightness.light);
    expect(AirColors.night.brightness, Brightness.dark);
  });
}
