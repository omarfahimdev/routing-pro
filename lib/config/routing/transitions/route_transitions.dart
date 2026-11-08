import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Named transitions, chosen per route on its spec rather than repeated at
/// every `pageBuilder`.
enum TransitionPreset {
  /// Platform-correct default: none on web, fade on mobile.
  adaptive,
  none,
  fade,
  scale,
  slideFromRight,
  slideFromLeft,
  slideFromTop,
  slideFromBottom,
  slideAndFade,
}

@immutable
class TransitionConfig {
  const TransitionConfig({
    this.duration = const Duration(milliseconds: 220),
    this.reverseDuration,
    this.curve = Curves.easeOutCubic,
    this.reverseCurve,
  });

  final Duration duration;
  final Duration? reverseDuration;
  final Curve curve;
  final Curve? reverseCurve;
}

abstract final class RouteTransitions {
  const RouteTransitions._();

  static const defaultConfig = TransitionConfig();

  /// Builds the page for a route, applying the spec's transition and wrapping
  /// the child so the browser tab title tracks navigation.
  ///
  /// Web resolves `adaptive` to no animation on purpose: animated transitions
  /// on browser back/forward read as lag, and at a till they cost real seconds
  /// per sale.
  static Page<T> buildPage<T extends Object?>({
    required GoRouterState state,
    required Widget child,
    required String title,
    TransitionPreset preset = TransitionPreset.adaptive,
    TransitionConfig config = defaultConfig,
    bool fullscreenDialog = false,
    String? restorationId,
  }) {
    final content = DocumentTitle(title: title, child: child);
    final key = state.pageKey;
    final name = state.name ?? state.matchedLocation;
    final effective = _resolve(preset);

    if (effective == TransitionPreset.none) {
      return NoTransitionPage<T>(key: key, name: name, restorationId: restorationId, child: content);
    }

    return CustomTransitionPage<T>(
      key: key,
      name: name,
      restorationId: restorationId,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: config.duration,
      reverseTransitionDuration: config.reverseDuration ?? config.duration,
      child: content,
      transitionsBuilder: (context, animation, secondary, child) {
        // Respect the OS "reduce motion" switch everywhere, for free.
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return _build(effective, animation, config, child);
      },
    );
  }

  static TransitionPreset _resolve(TransitionPreset preset) {
    if (preset != TransitionPreset.adaptive) return preset;
    return kIsWeb ? TransitionPreset.none : TransitionPreset.fade;
  }

  static Widget _build(TransitionPreset preset, Animation<double> animation, TransitionConfig config, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: config.curve, reverseCurve: config.reverseCurve);

    Widget slide(Offset begin, {bool fade = false}) {
      final position = Tween<Offset>(begin: begin, end: Offset.zero).animate(curved);
      final moved = SlideTransition(position: position, child: child);
      return fade ? FadeTransition(opacity: curved, child: moved) : moved;
    }

    return switch (preset) {
      TransitionPreset.fade => FadeTransition(opacity: curved, child: child),
      TransitionPreset.scale => ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      ),
      TransitionPreset.slideFromRight => slide(const Offset(1, 0)),
      TransitionPreset.slideFromLeft => slide(const Offset(-1, 0)),
      TransitionPreset.slideFromTop => slide(const Offset(0, -1)),
      TransitionPreset.slideFromBottom => slide(const Offset(0, 0.08), fade: true),
      TransitionPreset.slideAndFade => slide(const Offset(0.12, 0), fade: true),
      TransitionPreset.none || TransitionPreset.adaptive => child,
    };
  }
}

/// Drives the browser tab title and the Android recent label.
class DocumentTitle extends StatelessWidget {
  const DocumentTitle({required this.title, required this.child, super.key});

  static const appName = 'Cash Counter POS';

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Title(
    title: title.isEmpty ? appName : '$title \u00b7 $appName',
    color: Theme.of(context).colorScheme.primary,
    child: child,
  );
}
