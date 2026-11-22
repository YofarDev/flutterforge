---
name: flutter-lowend-perf
description: Measure and fix how a Flutter app (especially one with Rive animations) performs on low-end Android phones - scripted profile-mode take on a real device, per-screen frame stats, widget-build traces, Rive per-animation cost (census + ablation), then fixes such as resting idle Rive loops and adaptive "lite motion". Use for "simulate a lower-end phone", "is it smooth on cheap Android", "profile performance", "jank", "frame drops", "Rive is slow", "measure performance", "optimize for budget devices".
---

# Low-end Android performance (Flutter + Rive)

Goal: numbers per screen from the real app, the cause of every slow frame,
fixes the owner agreed to, and the same take re-measured to prove them.
Measure first; change nothing in the app until a measurement points at it.

Files in this skill:

| Path | What |
|---|---|
| `harness/perf_probe.dart` | Frame timings per phase, widget-build trace windows, report to the driver |
| `harness/rive_probe.dart` | Rive census (what ticks per phase) + ablation (cost of each animation) |
| `harness/perf_take_test.dart` | Template take test (the app's scripted path) |
| `harness/perf_driver.dart` | `flutter drive` host side |
| `scripts/perf_run.py` | Safe build → id check → install → drive → report |
| `scripts/perf_report.py` | Report one run or compare two |
| `scripts/lowend_avd.sh` | Low-end emulator (read its header: limited value) |
| `lib_templates/` | `MotionBudget` (adaptive lite motion), `LiteMotionScope` + `RiveRest`, its test |
| `REFERENCE.md` | Case study numbers, trace reading, Rive runtime facts, harness gotchas |

## Ground rules

- **A real phone beats any emulator.** Emulator cores run at host speed (UI
  thread as fast as a flagship); the software GPU is 10x slower than any
  phone. The emulator only shows memory/parallelism issues. See REFERENCE.md.
- **The flagship rule.** Budget phones are ~3–4x slower on the UI thread.
  On the owner's fast phone, a screen with UI build p50 > ~4 ms or frames
  constantly near 16.7 ms will stutter on low-end devices. Firebase Test Lab
  or a cheap used phone give true numbers; offer them, never upload without
  asking.
- **Profile mode only** (`--profile`). Debug numbers are meaningless.
- **Visual trade-offs are the owner's call.** Freezing an ambient loop,
  lowering effects, or making them device-dependent changes the design:
  present the measured cost and options (AskUserQuestion), then implement.
- **Same take before and after.** Compare with `perf_report.py a.json b.json`.

## Device safety (read before touching a phone)

The owner's phone has the real app with their data. `flutter drive` alone
resolves the app id from the manifest and **uninstalls the real app** when
an install fails, and uninstalls the test app after the run.

1. The perf build gets its own id: a define switches `applicationIdSuffix`
   (step Setup 1). `perf_run.py` refuses an APK whose id is not exactly
   `--package`, and refuses `--package == --real-package`.
2. Install with `adb install -r` only; drive with
   `--use-application-binary <apk> --keep-app-running --no-dds`.
   `perf_run.py` does all of this. Never run plain `flutter drive` on the
   owner's phone.
3. Pass defines as separate arguments. In zsh `D="--dart-define=A --dart-define=B"; flutter build $D`
   passes ONE argument → `A="true --dart-define=B"` → no suffix → the
   APK carries the REAL id. Use arrays or the script.
4. Before each run the phone must be unlocked, untouched, with no other
   Flutter app in front: drive attaches to the first Flutter VM it finds
   (it once measured the owner's other app). `perf_run.py` prints the
   foreground app. Force-stop leftovers of the perf app (it does).
5. Xiaomi/HyperOS asks the owner to accept every USB install: say so.

## Setup (once per app)

1. **App id suffix.** In `android/app/build.gradle.kts`, decode the
   dart-defines and switch the suffix (an app made for a film capture may
   already have one, e.g. `FILM_CAPTURE` → `.film`: reuse it with
   `perf_run.py --id-define FILM_CAPTURE=true`):

   ```kotlin
   val dartDefines = (project.findProperty("dart-defines") as? String).orEmpty()
       .split(",").mapNotNull { runCatching { String(java.util.Base64.getDecoder().decode(it)) }.getOrNull() }
       .mapNotNull { v -> v.indexOf('=').takeIf { it > 0 }?.let { v.substring(0, it) to v.substring(it + 1) } }
       .toMap()
   android { defaultConfig {
       if (dartDefines["PERF_CAPTURE"] == "true") applicationIdSuffix = ".perf"
   } }
   ```
   Check: `aapt dump badging build/app/outputs/flutter-apk/app-profile.apk | head -1`.
2. `flutter pub add dev:vm_service` (plus `integration_test` / `flutter_test`
   from the SDK if missing).
3. Copy `harness/perf_probe.dart` (and `rive_probe.dart` for Rive apps) to
   `integration_test/support/`, `harness/perf_driver.dart` to `test_driver/`,
   `harness/perf_take_test.dart` to `integration_test/`.
4. **Write the take** in `perf_take_test.dart`: the app's main path in 5–8
   screens, `probe.mark('<screen>')` at each, 2–3 s idle on each screen
   (idle frames expose loops that never rest). Reuse an existing capture
   harness (film / store screenshots) if the app has one: add the probe to
   it instead of writing a second take. Make it deterministic and offline:
   returning-user prefs, fake backend/ads/purchases, seeded content.
   Script taps by keys; type answers through `binding.testTextInput`
   (register it so the system keyboard never opens). Avoid pausing on a
   screen with a countdown.
5. `flutter analyze integration_test` clean.

## Workflow

Run from the app root. `S=~/.agents/skills/flutter-lowend-perf/scripts`.

**1. Baseline** (owner's phone; optional low-end emulator, `$S/lowend_avd.sh`):
```bash
uv run $S/perf_run.py --device <serial> --package <id>.perf --real-package <id> --tag baseline
```
Read: whole-take jank %, then the per-phase table. Rank screens by jank
and by build p90. A screen whose *idle* phase janks has an ambient cost.

**2. What runs per frame** (trace windows on the worst screens):
```bash
uv run $S/perf_run.py ... --tag trace --define PERF_TRACE=true --define PERF_TRACE_ON=home,play
```
- BeginFrame per frame ≫ BUILD per frame, few widget builds → the cost is
  ticker callbacks (Rive advance + draw encode, AnimationControllers), not
  rebuilds. Go to step 3.
- A widget built ~once per frame → a rebuild loop (setState/stream/
  AnimatedBuilder too high): narrow it (`BlocSelector`, `child:` param,
  `RepaintBoundary`).
- `Canvas::saveLayer` many per frame → Opacity/ShaderMask/BackdropFilter/
  ColorFiltered/ImageFiltered; costly on weak GPUs (raster column).

**3. Rive cost** (Rive apps):
```bash
uv run $S/perf_run.py ... --tag rive --define PERF_RIVE=true
```
The take must call `riveAblation(probe, pump: tester.pump)` on idle screens
(see template). Read the census (share of time each animation ticks per
phase; 1.0 = never rests) and the ablation (UI ms each one costs). In the
case study one menu scene cost 6.4 ms/frame and capped the menu at 36 fps;
four round loops cost ~2 ms each.

**4. Decide with the owner**, show the numbers, give 2–3 options (see the
catalogue), implement the chosen one following the app's architecture
skill, add tests, `flutter analyze`, run affected tests.

**5. Re-measure** the same take, same device, and compare:
```bash
uv run $S/perf_report.py build/perf/baseline.json build/perf/after.json
```
Report to the owner: a before/after table per screen, what changed visually,
what is still slow (with the next lead), what was not verified.

## Fix catalogue

| Problem (measured) | Fix |
|---|---|
| A Rive scene loops forever on an idle screen | **Rest after idle**: after its intro/event, run N s, then `controller.active = false` (freezes on the current frame, still drawn). Wake on pointer down (`Listener` on the screen), on route becoming current, on app resume. The owner decides N (12 s in the case study). |
| Rive keeps ticking under a covering route / in background | `active = false` when `ModalRoute.isCurrentOf(context) == false` and on `AppLifecycleState.paused/inactive/hidden`. |
| Many small ambient loops (buttons, mascot, flames) | **Adaptive lite motion** (`lib_templates/`): `MotionBudget` watches `FrameTiming`; when 30% of frames go over 16.7 ms in 2 windows of 120 (after 240 warm-up frames) it switches lite for the session. `LiteMotionScope` (InheritedNotifier) above MaterialApp; each Rive wrapper owns a `RiveRest` (`settle` 4–5 s) and calls `wake()` on every trigger, view-model value change, and touch. Loaders opt out (their loop *is* the message). The owner's fast phone may go lite too if it really janks somewhere: show them, let them choose thresholds. |
| Rebuild per frame | Narrow the rebuild scope; move animation into a leaf widget or `RepaintBoundary`. |
| Many saveLayers / raster-bound screen | Replace `Opacity` on subtrees with colour alpha or `FadeTransition` on a leaf; avoid stacked `BackdropFilter`; pre-bake glows into images; `RepaintBoundary` around static heavy art. |
| Rive scene too heavy even when needed | Fewer paths/feathers in the art, smaller artboard, `RiveWidget(renderResolution: ...)` for raster cost. |

Rive runtime facts (rive 0.14 / rive_native, verify on upgrades): there is
no frame-rate cap; `active = false` makes `advance` return false and the
ticker stop (last frame stays on screen); `active = true` restarts the
ticker with elapsed reset to 0 (so toggling cannot throttle to 30 fps);
the ticker honours `TickerMode`. Details in REFERENCE.md.

## Pitfalls (each one cost a run)

| Symptom | Cause / fix |
|---|---|
| APK has the real app id | zsh `$D` define string (Device safety 3) |
| Take passes in 10 s, report empty | drive attached to a leftover perf instance: force-stop it |
| Report empty, logs of another app | another Flutter app in front: ask the owner to close it |
| `Failed to connect to VM Service ... network disabled` | the take's HttpOverrides lockdown blocks localhost: `probe.connect()` before it, and `--no-dds` |
| Emulator `offline` after `taskpolicy -b` | background QoS starves qemu: don't |
| Software-GPU emulator timings | 10x slower than any phone: don't use |
| Ablation shows +8 ms when turning a view *off* | the app rested others; toggling woke them. `riveAblation` sets all running first. |
| `debugProfileBuildsEnabled` in profile | works in profile; adds overhead: trace runs are for *what*, not *how much* |
