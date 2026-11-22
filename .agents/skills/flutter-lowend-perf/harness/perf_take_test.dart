// Copy to <app>/integration_test/perf_take_test.dart and write the TAKE.
// Profile builds on a device only; NOT part of `flutter test`. Run it with
// the skill's scripts/perf_run.py (never plain `flutter drive` on a phone
// that has the real app installed: see SKILL.md, "Device safety").
//
// Defines: PERF_TRACE=true (+ PERF_TRACE_ON=phaseA,phaseB) widget-build
// trace windows; PERF_RIVE=true Rive census + ablations; PERF_CAPTURE=true
// must switch the Android applicationIdSuffix (see SKILL.md).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// TODO(app): your app widget and whatever main() sets up before runApp.
// import 'package:my_app/app.dart';
// import 'package:my_app/core/di/service_locator.dart';

import 'support/perf_probe.dart';
import 'support/rive_probe.dart'; // Rive apps only (delete otherwise)

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the device's pace (the default policy fakes them).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('perf take', (WidgetTester tester) async {
    final PerfProbe probe = PerfProbe(binding);
    // FIRST: before any HttpOverrides / network lockdown (VM service).
    await probe.connect();

    // TODO(app): the same setup main() does before runApp (DI, prefs,
    // fakes for backend/ads/purchases so the take is deterministic and
    // offline-safe). Prefer a returning-user state: onboarding done.
    // await setupServiceLocator();

    Future<void> settle(Duration d) async {
      await tester.pump();
      await Future<void>.delayed(d);
      await tester.pump();
    }

    Future<void> waitFor(
      Finder f, {
      Duration timeout = const Duration(seconds: 40),
    }) async {
      final Stopwatch w = Stopwatch()..start();
      while (f.evaluate().isEmpty) {
        if (w.elapsed > timeout) {
          fail('timed out waiting for $f');
        }
        await settle(const Duration(milliseconds: 100));
      }
    }

    // ignore: unused_element (used by the take you write)
    Future<void> tap(Finder f) async {
      await tester.tap(f, warnIfMissed: false);
      await tester.pump();
    }

    final RiveCensus? census = perfRive ? RiveCensus(probe) : null;
    probe.start();
    census?.start();
    probe.mark('launch');
    // TODO(app): await tester.pumpWidget(const MyApp());

    // ---- TAKE ---------------------------------------------------------
    // Script the app's real main path, 5–8 screens, the way a player uses
    // it. mark() each screen; let each screen sit idle 2–3 s (idle frames
    // show ambient cost: loops that should rest). Example:
    //
    // await waitFor(find.byKey(const ValueKey<String>('home-start')));
    // probe.mark('home');
    // await settle(const Duration(seconds: 3));
    // if (perfRive) {
    //   // the app may rest its own loops: measure as-is after that delay
    //   probe.extra['ablation:home'] = await riveAblation(
    //     probe, pump: tester.pump, restWait: const Duration(seconds: 13));
    // }
    // await tap(find.byKey(const ValueKey<String>('home-start')));
    // probe.mark('play');
    // ...
    // ---------------------------------------------------------------------

    probe.mark('end');
    await settle(const Duration(seconds: 2));
    if (census != null) {
      probe.extra['riveCensus'] = census.stop();
    }
    await probe.finish();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
