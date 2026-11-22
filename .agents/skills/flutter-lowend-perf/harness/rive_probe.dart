// Copy to <app>/integration_test/support/rive_probe.dart (Rive apps only;
// rive ^0.14: RiveWidget.controller, RiveWidgetController.active /
// isTickerActive).
//
// Answers "which Rive animations cost frames, and how much":
//
//  - RiveCensus: every 500 ms, which mounted RiveWidgets are ticking. Per
//    phase: the share of samples each one was ticking (1.0 = never rests).
//  - riveAblation(): on the current, idle screen, pauses each RiveWidget in
//    turn (controller.active = false) and measures the UI thread's mean
//    build time against all running and all paused. The drop is that
//    animation's per-frame cost (its state-machine advance + draw encode,
//    which run in the frame's transient callbacks: BeginFrame, not BUILD).
//
// Only pause on a screen nothing scripted is waiting on (no timers that
// expire, no pending input): the take stands still while it measures.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import 'perf_probe.dart';

/// `PERF_RIVE=true`: run the census and the ablations the take asks for.
const bool perfRive = bool.fromEnvironment('PERF_RIVE');

typedef RiveView = ({String label, rive.RiveWidgetController c});

/// Framework / wrapper types skipped when naming a RiveWidget's owner.
final RegExp _framework = RegExp(
  '^(_|Rive|Listener|GestureDetector|RawGestureDetector|Semantics|'
  'MergeSemantics|ExcludeSemantics|Center|Align|SizedBox|ConstrainedBox|'
  'Padding|Transform|Opacity|FadeTransition|ScaleTransition|'
  'SlideTransition|AnimatedBuilder|ListenableBuilder|ValueListenableBuilder|'
  'TweenAnimationBuilder|Builder|LayoutBuilder|StatefulBuilder|'
  'FutureBuilder|StreamBuilder|ClipRect|ClipRRect|ClipOval|OverflowBox|'
  'FittedBox|AspectRatio|Positioned|Stack|Expanded|Flexible|Row|Column|'
  'Container|DecoratedBox|ColoredBox|IgnorePointer|AbsorbPointer|'
  'MouseRegion|RepaintBoundary|KeyedSubtree|Offstage|Visibility|'
  'TickerMode|MediaQuery|Theme|DefaultTextStyle|IconTheme|Material|'
  'InkWell|Ink|Hero|SafeArea|Directionality|Focus|FocusScope|Actions|'
  'Shortcuts|BlocBuilder|BlocSelector|BlocListener|BlocConsumer|'
  'MultiBlocListener|Provider|InheritedWidget)',
);

/// Every mounted RiveWidget, labelled `<owner widget>/<artboard>`.
List<RiveView> riveViews() {
  final List<RiveView> out = <RiveView>[];
  void visit(Element e) {
    final Widget w = e.widget;
    if (w is rive.RiveWidget) {
      String owner = '?';
      e.visitAncestorElements((Element a) {
        final String t = a.widget.runtimeType.toString();
        if (_framework.hasMatch(t)) {
          return true;
        }
        owner = t;
        return false;
      });
      String art = '?';
      try {
        art = w.controller.artboard.name;
      } catch (_) {}
      out.add((label: '$owner/$art', c: w.controller));
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return out;
}

/// Samples which Rive views tick; report() groups samples by phase.
class RiveCensus {
  RiveCensus(this.probe);

  final PerfProbe probe;
  final List<Map<String, Object?>> _samples = <Map<String, Object?>>[];
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (Timer _) {
      _samples.add(<String, Object?>{
        'ms': probe.clock.elapsedMilliseconds,
        'ticking': <String>[
          for (final RiveView v in riveViews())
            if (v.c.isTickerActive) v.label,
        ],
      });
    });
  }

  Map<String, Object?> stop() {
    _timer?.cancel();
    final Map<String, Map<String, int>> hits = <String, Map<String, int>>{};
    final Map<String, int> count = <String, int>{};
    for (final Map<String, Object?> s in _samples) {
      final int ms = s['ms']! as int;
      String phase = 'pre';
      for (final Map<String, Object?> e in probe.events) {
        if ((e['ms']! as int) <= ms) {
          phase = '${e['type']}';
        }
      }
      count[phase] = (count[phase] ?? 0) + 1;
      for (final String l in s['ticking']! as List<String>) {
        final Map<String, int> h = hits.putIfAbsent(
          phase,
          () => <String, int>{},
        );
        h[l] = (h[l] ?? 0) + 1;
      }
    }
    return <String, Object?>{
      'samples': count,
      'ticking': <String, Object?>{
        for (final MapEntry<String, Map<String, int>> p in hits.entries)
          p.key: <String, double>{
            for (final MapEntry<String, int> h in p.value.entries)
              h.key: double.parse((h.value / count[p.key]!).toStringAsFixed(2)),
          },
      },
    };
  }
}

/// On the current idle screen: UI build time as it stands ('as_is', after
/// [restWait] when the app rests its own loops), with all running, each
/// paused in turn, and all paused. Restores every controller's `active`.
Future<Map<String, Object?>> riveAblation(
  PerfProbe probe, {
  required Future<void> Function() pump,
  Duration restWait = Duration.zero,
}) async {
  if (restWait > Duration.zero) {
    await pump();
    await Future<void>.delayed(restWait);
  }
  final Map<String, Object?> asIs = await probe.buildWindow(pump: pump);
  final List<RiveView> views = riveViews();
  final Map<RiveView, bool> was = <RiveView, bool>{
    for (final RiveView v in views) v: v.c.active,
  };
  final Map<String, Object?> out = <String, Object?>{
    'as_is': asIs,
    'views': <String>[
      for (final RiveView v in views)
        '${v.label} ticking=${v.c.isTickerActive}',
    ],
  };
  for (final RiveView v in views) {
    v.c.active = true;
  }
  out['all_running'] = await probe.buildWindow(pump: pump);
  for (final RiveView v in views) {
    v.c.active = false;
    out['off: ${v.label}'] = await probe.buildWindow(pump: pump);
    v.c.active = true;
  }
  for (final RiveView v in views) {
    v.c.active = false;
  }
  out['all_off'] = await probe.buildWindow(pump: pump);
  was.forEach((RiveView v, bool active) => v.c.active = active);
  return out;
}
