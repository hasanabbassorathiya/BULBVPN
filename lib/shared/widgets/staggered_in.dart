import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Critically-damped spring curve (stiffness 100, damping 20 — DESIGN.md §6).
/// Maps t∈[0,1] onto a spring settling from 0 to 1.
class SpringCurve extends Curve {
  SpringCurve({this.stiffness = 100, this.damping = 20, this.horizon = 0.6});

  final double stiffness;
  final double damping;
  final double horizon;

  late final SpringSimulation _sim = SpringSimulation(
    SpringDescription(mass: 1.0, stiffness: stiffness, damping: damping),
    1.0, // start at 1
    0.0, // decay to 0 (so 1 - x rises 0 → 1)
    0.0,
  );

  @override
  double transformInternal(double t) {
    return (1.0 - _sim.x(t * horizon)).clamp(0.0, 1.0);
  }
}

final SpringCurve kSpring = SpringCurve();

/// Waterfall entrance: opacity 0→1 + translateY 16→0 on a spring, delayed by
/// [delayMs]. Leaf widget — never re-renders its parent (DESIGN.md §6).
class StaggeredIn extends StatefulWidget {
  const StaggeredIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offset = 16,
  });

  final Widget child;
  final int delayMs;
  final double offset;

  @override
  State<StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    _anim = CurvedAnimation(parent: _controller, curve: kSpring);
    if (widget.delayMs <= 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _anim!.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Formats bytes-per-second for the metric rail: `842 KB/s`, `1.2 MB/s`.
String formatRate(num bytesPerSecond) {
  if (bytesPerSecond >= 1048576) {
    return '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

/// Formats a Duration as `HH:MM:SS` (tabular mono metric).
String formatDuration(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

double lerpAngle(double a, double b, double t) => a + (b - a) * t;

double smoothTowards(double current, double target, double dt, double rate) {
  return current + (target - current) * (1 - math.exp(-rate * dt));
}
