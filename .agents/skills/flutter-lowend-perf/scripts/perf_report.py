#!/usr/bin/env python3
"""Print a perf take report, or compare two.

    uv run perf_report.py build/perf/baseline.json [build/perf/after.json]

Reads the `perf` key PerfProbe writes (all, phases, traces, extra) and any
ablation / census blocks found anywhere in the file. With two files every
table shows A and B side by side (same take script, before/after a fix).

Reading it:
  build  = UI thread per frame (Dart: animations/tickers, build, layout,
           paint recording). Rive advance + draw encode land here.
  raster = GPU thread per frame (saveLayer, blurs, big images, shaders).
  jank   = frames with build or raster over 16.7 ms; severe = total > 33 ms.
  A flagship is ~3–4x faster than a budget phone on the UI thread: on a
  fast phone, build p50 above ~4 ms means trouble on low-end devices.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ENGINE_PREFIXES = ("Animator", "Vsync", "Rasterizer", "GPURasterizer", "SurfaceFrame", "LayerTree",
                   "Compositor", "Shell", "Platform", "Async", "Acquire", "Reclaim", "Check", "Clear",
                   "Create", "Destroy", "Semantics", "Canvas", "DartIsolate", "Engine", "Frame")
ENGINE_NAMES = {"BUILD", "LAYOUT", "PAINT", "COMPOSITING", "SEMANTICS", "FINALIZE TREE", "POST_FRAME",
                "UPDATING COMPOSITING BITS", "LAYOUT (root)", "PAINT (root)", "SEMANTICS (root)",
                "UPDATING COMPOSITING BITS (root)"}


def load(path: str) -> dict:
    d = json.loads(Path(path).read_text())
    return d if isinstance(d, dict) else {}


def perf(d: dict) -> dict:
    return d.get("perf") or {}


def fmt(v) -> str:
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:.1f}"
    return str(v)


def whole(runs: list[tuple[str, dict]]) -> None:
    keys = ["frames", "build_p50", "build_p90", "build_p99", "raster_p50", "raster_p90", "raster_p99",
            "worst_ms", "jank_16ms", "severe_33ms"]
    print("== whole take")
    print(f"  {'':12}" + "".join(f"{n[:14]:>16}" for n, _ in runs))
    for k in keys:
        print(f"  {k:12}" + "".join(f"{fmt(perf(d).get('all', {}).get(k)):>16}" for _, d in runs))
    for n, d in runs:
        a = perf(d).get("all", {})
        if a.get("frames"):
            print(f"  {n}: jank {100 * a['jank_16ms'] / a['frames']:.1f}%  severe {100 * a['severe_33ms'] / a['frames']:.1f}%")


def phases(runs: list[tuple[str, dict]]) -> None:
    """Aggregates repeated phases: frames, jank, severe, worst, max build/raster p90."""
    agg: list[dict[str, list]] = []
    order: list[str] = []
    for _, d in runs:
        g: dict[str, list] = {}
        for p in perf(d).get("phases", []):
            k = p["phase"]
            if k not in order:
                order.append(k)
            x = g.setdefault(k, [0, 0, 0, 0.0, 0.0, 0.0])
            x[0] += p.get("frames", 0)
            x[1] += p.get("jank_16ms", 0)
            x[2] += p.get("severe_33ms", 0)
            x[3] = max(x[3], p.get("worst_ms", 0))
            x[4] = max(x[4], p.get("build_p90", 0))
            x[5] = max(x[5], p.get("raster_p90", 0))
        agg.append(g)
    print("\n== per phase (frames / jank / severe / worst ms / max build p90 / max raster p90)")
    for k in order:
        cells = []
        for g in agg:
            x = g.get(k)
            cells.append("-" if not x else f"{x[0]:5}/{x[1]:4}/{x[2]:4}/{x[3]:5.0f}/{x[4]:5.1f}/{x[5]:5.1f}")
        print(f"  {k[:20]:20} " + "   ".join(f"{c:>36}" for c in cells))


def is_widget(name: str) -> bool:
    return name not in ENGINE_NAMES and not name.startswith(ENGINE_PREFIXES) and "::" not in name


def traces(runs: list[tuple[str, dict]]) -> None:
    for n, d in runs:
        tr = perf(d).get("traces") or d.get("builds") or {}
        for phase, t in tr.items():
            if not t:
                continue
            frames = t.get("frames") or 1
            top = t.get("top", [])
            print(f"\n== trace [{n}] {phase}: {t.get('frames')} frames")
            begin = next((e for e in top if e["name"] == "Animator::BeginFrame"), None)
            build = sum(e["ms"] for e in top if e["name"] in ("BUILD",))
            if begin:
                print(f"  UI per frame (BeginFrame) {begin['ms'] / frames:.1f} ms; BUILD phase {build / frames:.1f} ms"
                      " -> the gap is animation/ticker callbacks (Rive advance, AnimationControllers)")
            sl = next((e for e in top if e["name"] == "Canvas::saveLayer"), None)
            if sl:
                print(f"  saveLayer {sl['n'] / frames:.1f}/frame ({sl['ms']:.0f} ms total)")
            w = [e for e in top if is_widget(e["name"])]
            if w:
                print("  widgets built (count ~ frames = rebuilds every frame):")
                for e in w[:12]:
                    print(f"    {e['n']:6}  {e['ms']:7.1f} ms  {e['name']}")
            else:
                print("  no widget builds in the window: nothing rebuilds per frame")


def find_blocks(d, key: str, path: str = "") -> list[tuple[str, dict]]:
    out = []
    if isinstance(d, dict):
        if key in d:
            out.append((path or "root", d))
        for k, v in d.items():
            out += find_blocks(v, key, f"{path}.{k}" if path else k)
    return out


def ablations(runs: list[tuple[str, dict]]) -> None:
    for n, d in runs:
        for where, b in find_blocks(d, "all_off"):
            base = (b.get("all_running") or {}).get("build_mean")
            print(f"\n== Rive ablation [{n}] {where}  (UI build mean ms per frame; delta vs all running)")
            for k, v in b.items():
                if k == "views" or not isinstance(v, dict):
                    continue
                m = v.get("build_mean")
                delta = f"{m - base:+.1f}" if (m is not None and base is not None and k != "all_running") else ""
                print(f"  {k[:58]:58} {fmt(m):>6} {delta:>6}  frames={v.get('frames')}")


def census(runs: list[tuple[str, dict]]) -> None:
    for n, d in runs:
        for where, b in find_blocks(d, "ticking"):
            if not isinstance(b.get("ticking"), dict):
                continue
            print(f"\n== Rive census [{n}] {where}  (share of samples ticking; 1.0 = never rests)")
            for phase, t in b["ticking"].items():
                items = ", ".join(f"{k} {v:.2f}" for k, v in sorted(t.items(), key=lambda x: -x[1]))
                print(f"  {phase[:18]:18} {items}")


def main() -> None:
    files = sys.argv[1:]
    if not files or len(files) > 2:
        sys.exit(__doc__)
    runs = [(Path(f).stem, load(f)) for f in files]
    whole(runs)
    phases(runs)
    traces(runs)
    ablations(runs)
    census(runs)


if __name__ == "__main__":
    main()
