# flutter-lowend-perf reference

## Case study: Who Made This Movie (2026-11-22)

Flutter 3.50, rive 0.14.11, owner's POCO X6 Pro (2311DRK48G, fast,
60 Hz in profile runs). Take: launch → intro → menu → round of 7 films
(typed answers) → results → open a pack → card reveal → back to menu.

Baseline (whole take, ~5,300 frames): UI build p50 8.6 ms, p90 14.1;
raster p50 4.8; 482 frames over 16.7 ms, 560 over 33 ms.

| Finding | Evidence | Fix | After |
|---|---|---|---|
| No widget rebuilds per frame | trace: BeginFrame 9–12 ms/frame, BUILD+LAYOUT+PAINT ~1 ms, almost no widget build events | — | — |
| Menu intro scene (one big Rive artboard) loops forever | ablation: 10.1 → 3.7 ms when paused; 89 → 153 frames per 2.5 s (~36 → ~61 fps) | rest 12 s after last touch; wake on touch/route/resume; pause when covered | menu idle 2.0 ms/frame, ~61 fps |
| Round: mascot, Hint, Skip, streak flame loop 100% of the time | census 1.0; ablation ~1.5–2.6 ms each; all off 10.9 → 2.1 ms | adaptive lite motion (MotionBudget + RiveRest) | lite: round idle 2.2 ms; whole-take jank 10.8% → 5.9% |
| ~12 saveLayers per frame in the round | trace `Canvas::saveLayer` 2,089 in 3 s | not fixed (lead) | — |
| Owner's phone itself janks ~4 s on menu return after the pack (63–77% frames over budget) | per-phase table | owner kept thresholds: the phone goes lite there | open lead |

Low-end emulator (API 30, 2 cores, 1.5 GB, host GPU): UI times equal to
the flagship (cores at host speed); 12% frames over budget. SwiftShader:
raster median 205 ms, database copy 33 s, menu ready at 112 s — the take
timed out. `taskpolicy -b` on qemu: emulator went offline.

## Reading a trace window (PERF_TRACE)

`perf_probe.dart` records the `Dart` + `Embedder` timeline streams for
`traceWindow` after a mark, with `debugProfileBuildsEnabled = true` (one
event per widget build, named by type). Per-name counts and totals:

- `Animator::BeginFrame` ≈ the whole UI-thread frame. Inside it: transient
  callbacks (tickers: AnimationController, Rive's RiveWidget ticker →
  state machine `advanceAndApply` + draw encode through FFI), then
  `BUILD`, `LAYOUT`, `PAINT`, `COMPOSITING`, `SEMANTICS`, `FINALIZE TREE`.
  BeginFrame − (BUILD+LAYOUT+PAINT+…) = ticker cost. Dart code in tickers
  is not broken down: use the Rive ablation to attribute it.
- Widget build events: count ≈ frames in the window → rebuilt every frame.
  A few `Listener`/`RawGestureDetector` per frame are cheap.
- Raster: `GPURasterizer::Draw`, `LayerTree::Paint`, `SurfaceFrame::Submit`;
  `Canvas::saveLayer` count per frame is the main raster-cost lead.
- Frame counts differ between tools: FrameTiming counts produced frames;
  the trace counts BeginFrame. Compare like with like.

## Rive runtime (rive 0.14.11 / rive_native 0.1.11)

- `RiveWidgetController.advance(elapsed)` → `stateMachine.advanceAndApply`
  and returns `didAdvance && active`. When it returns false the render box
  stops its ticker; the last painted frame stays visible.
- `active` setter → `notifyListeners()`; setting true calls
  `restartTickerIfStopped()` → `startTicker()` resets elapsed to 0. So you
  cannot throttle a loop to N fps by toggling `active` (time would not
  advance properly), and a subclass that skips `advance` still repaints
  every tick (paint calls advance + draw). No built-in fps cap exists.
- A state machine that reaches a state with no running animation stops
  ticking by itself ("settles"). Endless idle loops never settle: that is
  what costs frames on idle screens.
- The ticker is created by the widget's TickerProvider: covered routes with
  `TickerMode` off stop it.
- `RiveWidget(renderResolution: ...)` lowers the texture resolution (raster
  cost), not the UI-thread advance/encode cost.
- `Factory.rive` (Rive renderer) is needed for feathers/glows; its draw is
  encoded on the UI thread at paint time and rendered into a texture.

## Harness notes

- `binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive`
  so the engine produces real frames at device pace; waits are
  `pump(); Future.delayed(d); pump();`.
- Touches: `tester.tap` works; a film/screenshot harness may send device
  events instead (`binding.handlePointerEventForSource`) to avoid the test
  crosshair. Either is fine for perf.
- Typing: `binding.testTextInput.register()` so the system keyboard never
  opens, then `tester.enterText` / `testTextInput.enterText`.
- Network lockdown via `HttpOverrides.global` (to make takes offline and
  deterministic) also blocks the VM service websocket: open the timeline
  connection first (`probe.connect()`), run drive with `--no-dds`.
- `integrationDriver` writes `binding.reportData` to
  `build/integration_response_data.json`; it is replaced on every run
  (`perf_run.py` deletes it first and copies it per tag).
- A full take is ~2–3 minutes on device plus ~1 minute build.
- The census timer walks the element tree every 500 ms between frames; its
  cost is negligible but it is not zero: do not run census and a precise
  ablation comparison in different runs and compare them.

## Lite motion design notes

- Budget 16.7 ms even on 90/120 Hz screens: the goal is "never below 60",
  not "always at the panel rate".
- Sticky by design: resting the loops removes the cost that triggered it.
- Wake on input, not on rebuild: compare old/new view-model maps before
  waking, otherwise a parent rebuilding every frame keeps loops awake.
- Settle long enough for event animations (stamps ~0.7–0.8 s, celebrations
  2–3 s, hint bubbles 4 s): 4 s for small effects, 5 s for a mascot.
- `forceLite()` exists for perf runs (`PERF_LITE` in the case study) and a
  possible user setting ("Reduce animations").
