// Copy to <app>/integration_test/support/perf_probe.dart.
// Needs dev dependencies: integration_test (sdk), flutter_test (sdk),
// vm_service (`flutter pub add dev:vm_service`).
//
// Frame-timing probe for a scripted take of the real app in profile mode.
// Reports to `build/integration_response_data.json` (via
// `integrationDriver`) under the key `perf`:
//
//   perf.all      whole-take frame stats
//   perf.phases   the same per phase (a phase runs from one mark() to the
//                 next)
//   perf.traces   (trace mode) widget-build / engine-event totals for a few
//                 seconds after selected marks
//   perf.extra    anything the take adds with probe.extra[...] = ...
//
// Times are in ms. "jank" = a frame whose UI (build) or raster time went
// over 16.7 ms; "severe" = total span over 33 ms.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

/// `PERF_TRACE=true`: also trace widget builds (debugProfileBuildsEnabled)
/// for [PerfProbe.traceWindow] after each mark listed in `PERF_TRACE_ON`
/// (comma separated; first occurrence only).
const bool perfTrace = bool.fromEnvironment('PERF_TRACE');
const String _traceOnArg = String.fromEnvironment('PERF_TRACE_ON');

class PerfProbe {
  PerfProbe(
    this.binding, {
    this.traceWindow = const Duration(seconds: 3),
    List<String>? traceOn,
  }) : traceOn =
           traceOn ??
           _traceOnArg.split(',').where((String s) => s.isNotEmpty).toList();

  final IntegrationTestWidgetsFlutterBinding binding;
  final Duration traceWindow;
  final List<String> traceOn;

  /// Run clock: ms 0 = [start].
  final Stopwatch clock = Stopwatch();
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  final List<Map<String, int>> timings = <Map<String, int>>[];
  final Map<String, Object?> extra = <String, Object?>{};

  final Map<String, Object?> _traces = <String, Object?>{};
  Future<void> _tracing = Future<void>.value();
  bool _started = false;

  /// Call FIRST in the test body, before any HttpOverrides / network
  /// lockdown: the binding caches its VM-service websocket, and a lockdown
  /// that refuses localhost makes every later trace fail.
  Future<void> connect() async {
    if (perfTrace) {
      await binding.enableTimeline(streams: const <String>['Dart', 'Embedder']);
    }
  }

  /// Starts the clock and the frame-timing callback.
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    if (perfTrace) {
      debugProfileBuildsEnabled = true;
    }
    clock.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> list) {
    for (final FrameTiming t in list) {
      timings.add(<String, int>{
        'ms': clock.elapsedMilliseconds,
        'build': t.buildDuration.inMicroseconds,
        'raster': t.rasterDuration.inMicroseconds,
        'total': t.totalSpan.inMicroseconds,
      });
    }
  }

  /// Starts a phase. Phases name what the screen is doing ("menu",
  /// "question", "packOpen"...), so the report reads per screen.
  void mark(
    String phase, [
    Map<String, Object?> more = const <String, Object?>{},
  ]) {
    events.add(<String, Object?>{
      'ms': clock.elapsedMilliseconds,
      'type': phase,
      ...more,
    });
    if (perfTrace && traceOn.contains(phase) && !_traces.containsKey(phase)) {
      _traces[phase] = null;
      _tracing = _tracing.then((_) async {
        final vm.Timeline t = await binding.traceTimeline(
          () => Future<void>.delayed(traceWindow),
          streams: const <String>['Dart', 'Embedder'],
        );
        _traces[phase] = _traceReport(t);
      });
    }
  }

  /// UI-thread build time over [measure] real time, after [lead] to let a
  /// change take effect. [pump] keeps the engine producing frames (pass the
  /// tester's pump in a live-policy test).
  Future<Map<String, Object?>> buildWindow({
    required Future<void> Function() pump,
    Duration lead = const Duration(milliseconds: 500),
    Duration measure = const Duration(milliseconds: 2500),
  }) async {
    await pump();
    await Future<void>.delayed(lead);
    final int from = clock.elapsedMilliseconds;
    await Future<void>.delayed(measure);
    await pump();
    final List<int> b =
        timings
            .where((Map<String, int> t) => t['ms']! >= from)
            .map((Map<String, int> t) => t['build']!)
            .toList()
          ..sort();
    if (b.isEmpty) {
      return <String, Object?>{'frames': 0};
    }
    final double mean = b.reduce((int a, int c) => a + c) / b.length / 1000;
    return <String, Object?>{
      'frames': b.length,
      'build_mean': double.parse(mean.toStringAsFixed(2)),
      'build_p90': b[((b.length - 1) * 0.9).round()] / 1000,
    };
  }

  /// Stops collecting and hands the report to the driver.
  Future<void> finish() async {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    await _tracing;
    debugProfileBuildsEnabled = false;
    binding.reportData = <String, dynamic>{
      'perf': <String, Object?>{
        ..._report(),
        if (perfTrace) 'traces': _traces,
        if (extra.isNotEmpty) 'extra': extra,
      },
    };
  }

  Map<String, Object?> _report() {
    final List<Map<String, Object?>> phases = <Map<String, Object?>>[];
    for (int i = 0; i < events.length; i++) {
      final int from = events[i]['ms']! as int;
      final int to = i + 1 < events.length
          ? events[i + 1]['ms']! as int
          : 1 << 30;
      final List<Map<String, int>> f = timings
          .where((Map<String, int> e) => e['ms']! >= from && e['ms']! < to)
          .toList();
      if (f.isEmpty) {
        continue;
      }
      phases.add(<String, Object?>{
        'phase': events[i]['type'],
        'from_ms': from,
        ...frameStats(f),
      });
    }
    return <String, Object?>{'all': frameStats(timings), 'phases': phases};
  }
}

/// Frame stats in ms; budget 16.7 ms (60 Hz).
Map<String, Object?> frameStats(List<Map<String, int>> f) {
  if (f.isEmpty) {
    return <String, Object?>{'frames': 0};
  }
  double pct(String k, double p) {
    final List<int> v = f.map((Map<String, int> e) => e[k]!).toList()..sort();
    return v[((v.length - 1) * p).round()] / 1000;
  }

  return <String, Object?>{
    'frames': f.length,
    'build_p50': pct('build', 0.5),
    'build_p90': pct('build', 0.9),
    'build_p99': pct('build', 0.99),
    'raster_p50': pct('raster', 0.5),
    'raster_p90': pct('raster', 0.9),
    'raster_p99': pct('raster', 0.99),
    'worst_ms': pct('total', 1),
    'jank_16ms': f
        .where(
          (Map<String, int> e) => e['build']! > 16667 || e['raster']! > 16667,
        )
        .length,
    'severe_33ms': f.where((Map<String, int> e) => e['total']! > 33333).length,
  };
}

/// Engine + widget events in one traced window: per name the count and
/// total ms, top 40 by count. With debugProfileBuildsEnabled every widget
/// build is an event named after its type: a widget whose count ≈ the
/// frame count rebuilds every frame.
Map<String, Object?> _traceReport(vm.Timeline t) {
  final Map<String, List<num>> by = <String, List<num>>{};
  final Map<int, List<Map<String, dynamic>>> open =
      <int, List<Map<String, dynamic>>>{};
  int frames = 0;
  void add(String name, num durUs) {
    final List<num> v = by.putIfAbsent(name, () => <num>[0, 0]);
    v[0] += 1;
    v[1] += durUs / 1000;
  }

  for (final vm.TimelineEvent e in t.traceEvents ?? <vm.TimelineEvent>[]) {
    final Map<String, dynamic> j = e.json!;
    final String name = '${j['name']}';
    final String ph = '${j['ph']}';
    final int tid = (j['tid'] as num?)?.toInt() ?? 0;
    if (name == 'Animator::BeginFrame' && ph != 'E') {
      frames++;
    }
    if (ph == 'X') {
      add(name, (j['dur'] as num?) ?? 0);
    } else if (ph == 'B') {
      open.putIfAbsent(tid, () => <Map<String, dynamic>>[]).add(j);
    } else if (ph == 'E') {
      final List<Map<String, dynamic>>? st = open[tid];
      if (st != null && st.isNotEmpty) {
        final Map<String, dynamic> b = st.removeLast();
        add('${b['name']}', (j['ts'] as num) - (b['ts'] as num));
      }
    }
  }
  final List<MapEntry<String, List<num>>> top = by.entries.toList()
    ..sort(
      (MapEntry<String, List<num>> a, MapEntry<String, List<num>> b) =>
          b.value[0].compareTo(a.value[0]),
    );
  return <String, Object?>{
    'frames': frames,
    'events': t.traceEvents?.length ?? 0,
    'top': <Map<String, Object?>>[
      for (final MapEntry<String, List<num>> e in top.take(40))
        <String, Object?>{
          'name': e.key,
          'n': e.value[0],
          'ms': double.parse(e.value[1].toStringAsFixed(2)),
        },
    ],
  };
}
