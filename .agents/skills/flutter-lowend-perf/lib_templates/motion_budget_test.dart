// Template: test/.../motion_budget_test.dart (replace APP_PACKAGE).
import 'package:flutter_test/flutter_test.dart';
import 'package:APP_PACKAGE/core/services/motion_budget.dart';

const Duration _fast = Duration(milliseconds: 6);
const Duration _slow = Duration(milliseconds: 24);

/// Feeds [count] frames, [slowEvery] of which (1 in N) go over budget on
/// the UI thread; 0 = all fast.
void _feed(MotionBudget budget, int count, {int slowEvery = 0}) {
  for (int i = 0; i < count; i++) {
    final bool slow = slowEvery > 0 && i % slowEvery == 0;
    budget.recordFrame(build: slow ? _slow : _fast, raster: _fast);
  }
}

/// Defaults (30% slow share, two windows) on small windows.
MotionBudget _budget() => MotionBudget(warmupFrames: 10, windowFrames: 10);

void main() {
  test('starts in full motion and stays there on fast frames', () {
    final MotionBudget budget = _budget();
    _feed(budget, 200);
    expect(budget.lite, isFalse);
  });

  test('ignores slow warm-up frames', () {
    final MotionBudget budget = _budget();
    _feed(budget, 10, slowEvery: 1);
    _feed(budget, 100);
    expect(budget.lite, isFalse);
  });

  test('two consecutive slow windows switch to lite and notify once', () {
    final MotionBudget budget = _budget();
    int notified = 0;
    budget.addListener(() => notified++);
    _feed(budget, 10);
    _feed(budget, 20, slowEvery: 2);
    expect(budget.lite, isTrue);
    expect(notified, 1);
  });

  test('one slow window between fast ones does not switch', () {
    final MotionBudget budget = _budget();
    _feed(budget, 10);
    _feed(budget, 10, slowEvery: 2);
    _feed(budget, 10);
    _feed(budget, 10, slowEvery: 2);
    expect(budget.lite, isFalse);
  });

  test('raster over budget counts as slow too', () {
    final MotionBudget budget = _budget();
    _feed(budget, 10);
    for (int i = 0; i < 20; i++) {
      budget.recordFrame(build: _fast, raster: _slow);
    }
    expect(budget.lite, isTrue);
  });

  test('lite is sticky: fast frames afterwards keep it', () {
    final MotionBudget budget = _budget();
    _feed(budget, 10);
    _feed(budget, 20, slowEvery: 1);
    _feed(budget, 500);
    expect(budget.lite, isTrue);
  });

  test('forceLite switches at once and notifies once', () {
    final MotionBudget budget = _budget();
    int notified = 0;
    budget.addListener(() => notified++);
    budget
      ..forceLite()
      ..forceLite();
    expect(budget.lite, isTrue);
    expect(notified, 1);
  });
}
