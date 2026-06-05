import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppTransitions {
  /// Fade transition with optional scale effect
  static PageRouteBuilder fadeRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 300),
    bool withScale = false,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (withScale) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        }
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  /// Slide transition with direction
  static PageRouteBuilder slideRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 350),
    SlideDirection direction = SlideDirection.right,
    Curve curve = Curves.easeOutCubic,
  }) {
    final begin = switch (direction) {
      SlideDirection.right => const Offset(1.0, 0.0),
      SlideDirection.left => const Offset(-1.0, 0.0),
      SlideDirection.up => const Offset(0.0, 1.0),
      SlideDirection.down => const Offset(0.0, -1.0),
    };
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween(
            begin: begin,
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: curve)),
          child: child,
        );
      },
    );
  }

  /// Scale transition (zoom in/out)
  static PageRouteBuilder scaleRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 400),
    Curve curve = Curves.easeOutBack,
    double beginScale = 0.0,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: Tween<double>(
            begin: beginScale,
            end: 1.0,
          ).animate(CurvedAnimation(parent: animation, curve: curve)),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  /// Rotation + scale transition (interesting effect)
  static PageRouteBuilder rotateScaleRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 500),
    Curve curve = Curves.easeInOutBack,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return RotationTransition(
          turns: Tween<double>(
            begin: -0.1,
            end: 0.0,
          ).animate(CurvedAnimation(parent: animation, curve: curve)),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).animate(CurvedAnimation(parent: animation, curve: curve)),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
    );
  }

  /// Slide + fade with staggered effect
  static PageRouteBuilder staggeredSlideRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 450),
    SlideDirection direction = SlideDirection.right,
  }) {
    final begin = switch (direction) {
      SlideDirection.right => const Offset(1.0, 0.0),
      SlideDirection.left => const Offset(-1.0, 0.0),
      SlideDirection.up => const Offset(0.0, 1.0),
      SlideDirection.down => const Offset(0.0, -1.0),
    };
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Staggered effect: slide first, then fade
        return SlideTransition(
          position: Tween(begin: begin, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 3D flip transition
  static PageRouteBuilder flipRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final value = animation.value;
            final angle = value * math.pi / 2;
            final transform = Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(angle);
            return Transform(
              transform: transform,
              alignment: Alignment.center,
              child: Opacity(
                opacity: value < 0.5 ? value * 2 : (1 - value) * 2,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

enum SlideDirection { right, left, up, down }

/// Smooth fade + scale transition for widgets appearing/disappearing
class SmoothAnimatedWidget extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;
  final double beginScale;
  final double endScale;
  final Curve curve;

  const SmoothAnimatedWidget({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.beginScale = 0.8,
    this.endScale = 1.0,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: visible
          ? KeyedSubtree(key: const ValueKey('visible'), child: child)
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

/// Animated slide transition for widgets
class SlideAnimatedWidget extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;
  final Offset offset;

  const SlideAnimatedWidget({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.offset = const Offset(0, 1),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(begin: offset, end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: visible
          ? KeyedSubtree(key: const ValueKey('visible'), child: child)
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

/// Animated fade transition for widgets
class FadeAnimatedWidget extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;

  const FadeAnimatedWidget({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: visible
          ? KeyedSubtree(key: const ValueKey('visible'), child: child)
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}
