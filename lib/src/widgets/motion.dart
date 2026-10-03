import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Showcase motion kit, hand-rolled (no new dependencies).
///
/// Every entrance respects [MediaQuery.disableAnimationsOf]: when the
/// platform asks for reduced motion, widgets render their final frame
/// immediately instead of animating.

/// Frosted-glass card: blur + [SfsDecor.glass] paint. Keep blurred areas
/// small (cards, sheets, pills) — fullscreen backdrop blur is a GPU sink.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = SfsRadii.card,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final glass = SfsGlass.of(pal);
    final body = Container(
      padding: padding,
      decoration: SfsDecor.glass(pal, radius: radius),
      child: child,
    );
    final frosted = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
        child: body,
      ),
    );
    if (onTap == null) return frosted;
    return GestureDetector(onTap: onTap, child: frosted);
  }
}

/// Cascading entrance: children fade + rise with a per-index delay.
/// [animationId] restarts the cascade (e.g. pass the list fingerprint).
class StaggerList extends StatelessWidget {
  const StaggerList({
    super.key,
    required this.children,
    this.animationId = '',
    this.step = const Duration(milliseconds: 45),
    this.slide = 14.0,
  });

  final List<Widget> children;
  final Object animationId;
  final Duration step;
  final double slide;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          _Entrance(
            key: ValueKey('$animationId:$i'),
            delay: step * i,
            slide: slide,
            child: children[i],
          ),
      ],
    );
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({
    super.key,
    required this.delay,
    required this.slide,
    required this.child,
  });

  final Duration delay;
  final double slide;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  late final Animation<Offset> _rise = Tween(
    begin: Offset(0, widget.slide / 100),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _rise, child: widget.child),
    );
  }
}

/// Shimmering skeleton placeholder for loading rows. One shared shimmer per
/// list (wrap the list, not each row) to keep shader cost flat.
class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({
    super.key,
    required this.child,
    this.base,
    this.highlight,
  });

  final Widget child;
  final Color? base;
  final Color? highlight;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1 - _ctrl.value * 2, 0),
          end: Alignment(1 - _ctrl.value * 2, 0),
          colors: [
            widget.base ?? pal.surfaceOverlay,
            widget.highlight ?? pal.accentDim,
            widget.base ?? pal.surfaceOverlay,
          ],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(bounds),
        child: widget.child,
      ),
    );
  }
}

/// Springy modal sheet: rises with a soft overshoot instead of the stock
/// linear glide. Built on [showGeneralDialog] so the transition curve is
/// fully custom; barrier and chrome match the glass system.
Future<T?> showSpringSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (context, _, _) {
      final height = MediaQuery.of(context).size.height;
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: height * 0.9,
            minWidth: MediaQuery.of(context).size.width,
          ),
          child: _SheetChrome(child: builder(context)),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final rise = Tween(begin: const Offset(0, 0.12), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: const ElasticOutCurve(0.72),
              reverseCurve: Curves.easeInCubic,
            ),
          );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(position: rise, child: child),
      );
    },
  );
}

/// Spring sheet chrome: glass surface with a grabber.
class _SheetChrome extends StatelessWidget {
  const _SheetChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final glass = SfsGlass.of(pal);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(SfsRadii.sheet),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
        child: Container(
          decoration: BoxDecoration(
            color: glass.tint,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SfsRadii.sheet),
            ),
            border: Border(top: BorderSide(color: glass.border)),
          ),
          child: SafeArea(
            top: false,
            // showGeneralDialog (unlike showModalBottomSheet) provides no
            // Material ancestor: without this, ListTile/InkWell descendants
            // throw "No Material widget found".
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: pal.muted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass toast: frosted snackbar matching the chrome. Use for confirmations
/// on the converted screens; legacy screens keep the themed default.
void showGlassToast(BuildContext context, String message, {IconData? icon}) {
  final pal = SfsPalette.of(context);
  final glass = SfsGlass.of(pal);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: glass.tint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: glass.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon ?? Icons.check_circle_outlined,
                    size: 18,
                    color: pal.accent,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(color: pal.text, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
}

/// Shared-axis page transition for pushed screens (subtle X glide + fade).
PageRouteBuilder<T> glassPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final slide = Tween(begin: const Offset(0.06, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}
