// Template: lib/core/services/motion_budget.dart (FlutterForge layout).
// Register as a lazy singleton in service_locator.dart and start() it in
// the app shell; see SKILL.md "Fix catalogue".
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../utils/app_logger.dart';

/// Watches real frame timings and switches the app to *lite motion* when
/// the device keeps missing the 60 Hz frame budget.
///
/// Lite motion rests ambient Rive loops (idle breathing, flickers, orbits)
/// between events; event animations still play. Measured 2026-11-22 on a
/// fast phone: the round's four ambient loops cost ~9 ms of UI thread per
/// frame, so a budget phone would drop to ~25–30 fps with them running.
///
/// The decision is sticky for the session: once lite, the loops stop
/// costing frames, so recovering would only make the device flap between
/// the two modes. The first [warmupFrames] frames (startup, shader warm-up)
/// are ignored. A window counts as slow when at least [slowShare] of its
/// frames went over budget on the UI or raster thread; [slowWindows]
/// consecutive slow windows switch to lite.
class MotionBudget extends ChangeNotifier {
  MotionBudget({
    this.budget = const Duration(microseconds: 16667),
    this.warmupFrames = 240,
    this.windowFrames = 120,
    this.slowShare = 0.3,
    this.slowWindows = 2,
  });

  final Duration budget;
  final int warmupFrames;
  final int windowFrames;
  final double slowShare;
  final int slowWindows;

  bool _lite = false;
  bool _listening = false;
  int _seen = 0;
  int _inWindow = 0;
  int _overInWindow = 0;
  int _slowRun = 0;

  /// Whether ambient motion should rest between events.
  bool get lite => _lite;

  /// Starts watching frame timings (idempotent).
  void start() {
    if (_listening || _lite) {
      return;
    }
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _stop() {
    if (!_listening) {
      return;
    }
    _listening = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      recordFrame(build: t.buildDuration, raster: t.rasterDuration);
      if (_lite) {
        return;
      }
    }
  }

  /// Switches to lite motion now (perf runs, tests).
  void forceLite() {
    if (_lite) {
      return;
    }
    _lite = true;
    _stop();
    notifyListeners();
  }

  /// Feeds one frame; public for tests.
  @visibleForTesting
  void recordFrame({required Duration build, required Duration raster}) {
    if (_lite) {
      return;
    }
    if (++_seen <= warmupFrames) {
      return;
    }
    _inWindow++;
    if (build > budget || raster > budget) {
      _overInWindow++;
    }
    if (_inWindow < windowFrames) {
      return;
    }
    final double share = _overInWindow / _inWindow;
    _inWindow = 0;
    _overInWindow = 0;
    _slowRun = share >= slowShare ? _slowRun + 1 : 0;
    if (_slowRun >= slowWindows) {
      AppLogger.d(
        'MotionBudget: frames over budget (${(share * 100).round()}% of the '
        'last window): lite motion on',
      );
      _lite = true;
      _stop();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
