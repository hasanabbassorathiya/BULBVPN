import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

Color pingColor(int ping) {
  if (ping < 30) return AppColors.connected;
  if (ping < 80) return AppColors.primary;
  if (ping < 150) return AppColors.warning;
  return AppColors.error;
}

String formatDuration(Duration duration) {
  final h = duration.inHours.toString().padLeft(2, '0');
  final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String formatBytes(double bytes) {
  if (bytes > 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  } else if (bytes > 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else if (bytes > 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${bytes.toStringAsFixed(0)} B';
}

String formatSpeed(double bytesPerSecond) {
  final mbps = (bytesPerSecond * 8) / (1024 * 1024);
  if (mbps >= 1.0) {
    return '${mbps.toStringAsFixed(1)} Mbps';
  }
  return '${(mbps * 1024).toStringAsFixed(0)} Kbps';
}
