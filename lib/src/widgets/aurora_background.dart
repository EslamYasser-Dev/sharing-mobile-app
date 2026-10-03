import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Slow-drifting aurora wash painted behind glass surfaces.
///
/// Three radial blobs (accent → violet → cyan) orbit lazily on a single
/// ticker. The painter is wrapped in a [RepaintBoundary] so the drift never
/// repaints the content above it, and collapses to one static frame when the
/// platform disables animations (accessibility / battery saver).
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child, this.opacity = 1});

  final Widget? child;
  final double opacity;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final glass = SfsGlass.of(pal);
    final animationsOff = MediaQuery.disableAnimationsOf(context);
    Widget wash(double phase) => CustomPaint(
      painter: _AuroraPainter(
        a: glass.auroraA,
        b: glass.auroraB,
        c: glass.auroraC,
        background: pal.background,
        phase: phase,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // One isolated layer: the drift repaints only inside this boundary,
        // never the content above it.
        RepaintBoundary(
          child: animationsOff
              ? wash(0.35)
              : AnimatedBuilder(
                  animation: _drift,
                  builder: (_, _) => wash(_drift.value),
                ),
        ),
        if (widget.child != null)
          Opacity(opacity: widget.opacity, child: widget.child!),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.a,
    required this.b,
    required this.c,
    required this.background,
    this.phase = 0.35,
  });

  final Color a;
  final Color b;
  final Color c;
  final Color background;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = background,
    );
    final w = size.width;
    final h = size.height;
    final t = phase * math.pi * 2;
    _blob(canvas, size, Offset(w * (0.78 + 0.08 * math.sin(t)), h * 0.06), w * 0.55, a);
    _blob(canvas, size, Offset(w * (0.10 + 0.07 * math.cos(t * 0.8)), h * 0.30), w * 0.48, b);
    _blob(canvas, size, Offset(w * (0.55 + 0.09 * math.sin(t * 0.6 + 2)), h * 0.72), w * 0.60, c);
  }

  void _blob(Canvas canvas, Size size, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(
          Rect.fromCircle(center: center, radius: radius),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.phase != phase ||
      old.a != a ||
      old.b != b ||
      old.c != c ||
      old.background != background;
}
