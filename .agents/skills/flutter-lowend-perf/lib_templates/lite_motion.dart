// Template: lib/features/shared/widgets/lite_motion.dart (Rive apps).
// Provide LiteMotionScope above MaterialApp; give each Rive wrapper a
// RiveRest and wake() it on every input (trigger, value change, touch).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../../../core/services/motion_budget.dart';

/// Provides the app's [MotionBudget] to the widget tree; dependents rebuild
/// when it switches to lite motion.
class LiteMotionScope extends InheritedNotifier<MotionBudget> {
  const LiteMotionScope({
    super.key,
    required MotionBudget budget,
    required super.child,
  }) : super(notifier: budget);

  /// Whether ambient motion rests between events. False without a scope
  /// (widget tests): full motion.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LiteMotionScope>()
          ?.notifier
          ?.lite ??
      false;
}

/// Rests one Rive controller between events under lite motion.
///
/// Full motion: the controller always runs. Lite motion: each [wake] runs
/// it for [settle] (long enough for an event animation to play out), then
/// it stops ticking on its current pose until the next [wake]. Owners wake
/// it on every input they push (triggers, view-model values, pointer
/// down) so nothing they ask for is swallowed.
class RiveRest {
  RiveRest({this.settle = const Duration(seconds: 4)});

  final Duration settle;

  rive.RiveWidgetController? _controller;
  bool _lite = false;
  Timer? _timer;

  /// The controller to rest; wakes it at once.
  rive.RiveWidgetController? get controller => _controller;
  set controller(rive.RiveWidgetController? controller) {
    _controller = controller;
    wake();
  }

  /// Whether it rests between wakes (lite motion).
  bool get lite => _lite;

  /// Switches between full and lite motion.
  set lite(bool lite) {
    if (lite == _lite) {
      return;
    }
    _lite = lite;
    wake();
  }

  /// Runs the controller now and, under lite motion, rests it after
  /// [settle].
  void wake() {
    _timer?.cancel();
    _timer = null;
    final rive.RiveWidgetController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (!controller.active) {
      controller.active = true;
    }
    if (_lite) {
      _timer = Timer(settle, () => _controller?.active = false);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller = null;
  }
}
