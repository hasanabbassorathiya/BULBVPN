import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AppIconGenerator {
  static Future<void> generateIcons() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1024, 1024));

    _drawIcon(canvas, 1024);

    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 1024);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      final buffer = byteData.buffer.asUint8List();
      final file = File('assets/images/app_icon.png');
      await file.writeAsBytes(buffer);
    }
  }

  static void _drawIcon(Canvas canvas, double size) {
    final center = Offset(size / 2, size / 2);
    final radius = size * 0.42;

    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(size, size),
        [const Color(0xFF0A0F1C), const Color(0xFF1A2332)],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size, size),
        Radius.circular(size * 0.22),
      ),
      bgPaint,
    );

    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius * 1.5,
        [const Color(0xFF00E5C0).withValues(alpha: 0.3), const Color(0xFF00E5C0).withValues(alpha: 0)],
      );
    canvas.drawCircle(center, radius * 1.5, glowPaint);

    final boltPath = Path();
    final s = size * 0.35;
    final cx = size / 2;
    final cy = size / 2;

    boltPath.moveTo(cx + s * 0.15, cy - s * 0.5);
    boltPath.lineTo(cx - s * 0.35, cy + s * 0.05);
    boltPath.lineTo(cx + s * 0.05, cy + s * 0.05);
    boltPath.lineTo(cx - s * 0.15, cy + s * 0.5);
    boltPath.lineTo(cx + s * 0.35, cy - s * 0.05);
    boltPath.lineTo(cx - s * 0.05, cy - s * 0.05);
    boltPath.close();

    final boltPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - s, cy - s),
        Offset(cx + s, cy + s),
        [const Color(0xFF00E5C0), const Color(0xFF9B59B6)],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(boltPath, boltPaint);

    final shieldPath = Path();
    shieldPath.moveTo(cx, cy - radius * 0.7);
    shieldPath.lineTo(cx + radius * 0.6, cy - radius * 0.4);
    shieldPath.lineTo(cx + radius * 0.6, cy + radius * 0.1);
    shieldPath.quadraticBezierTo(cx + radius * 0.6, cy + radius * 0.5, cx, cy + radius * 0.7);
    shieldPath.quadraticBezierTo(cx - radius * 0.6, cy + radius * 0.5, cx - radius * 0.6, cy + radius * 0.1);
    shieldPath.lineTo(cx - radius * 0.6, cy - radius * 0.4);
    shieldPath.close();

    final shieldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.025
      ..color = const Color(0xFF00E5C0).withValues(alpha: 0.4);
    canvas.drawPath(shieldPath, shieldPaint);
  }
}
