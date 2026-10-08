---
name: "rive"
description: "Use when building, animating, verifying, or debugging Rive graphics with the Rive CLI — RML scenes, Luau scripts, view-model data binding, state machines, headless screenshot/pointer verification, .riv builds. Triggers include: 'rive', 'RML', '.riv file', 'rive animation', 'rive cli', 'press to talk button', 'rive character', 'rive card/component', or any request to build/inspect/export Rive graphics. Also covers reverse-engineering bare .riv files."
---

# Rive CLI — Agent Playbook

Verified against rive 1.4.0 (2026-10-08). See **Evolution protocol** before editing.

Project-generated `AGENTS.md` covers basics; this records costly traps from CLI 1.0.x–1.4.0.

## Core loop

```bash
rive create myproject && cd myproject    # scaffolds scene.rml, AGENTS.md, rive.yaml
rive schema <Type> [--animatable|--bindable|--all|--json]   # lookups FIRST; never guess types/keys
rive docs <topic>          # workflow gotchas format data state-machines layout text luau/protocols
# author in PASSES: wireframe (every box FILLED, fixed/fill sized) → structure → content → detail
# after EVERY edit: verify. At pass milestones: ALSO screenshot.
rive . --verify --format=json            # JSON on stdout; logs/errors on STDERR; lines/columns are 1-based
rive . --screenshot=build/s.png --advance=1   # advance=0 = rest pose; N renders frame N-1
```

`--verify` compiles + re-imports; it never renders a pixel or runs a script.

## Quality & completion gate

Read generated AGENTS.md + `rive --version`; pin acceptance criteria. Green
build ≠ done — prove three tiers, then report outputs + evidence + limits:
1. TECHNICAL: `--verify` green AND no runtime errors from THIS run (`logs.file`
   is append-only — old failures linger) AND positive proof the script RAN:
   one observable effect (print marker / changed frame / data-dump value).
   No errors ≠ executed — scripts can compile, render, and never run.
2. BEHAVIORAL: interactions fire (pointer proof / `--data-dump` "changed").
   Fixed-duration loops: `--advance=1` vs `<duration+1>` pixel-identical;
   procedural/time-driven animation: check continuity, not pixel identity.
3. VISUAL: single frames hide pops/clipping/bad arcs — render 6-10 frames of
   any nontrivial animation as a contact sheet/GIF (PIL) and judge against
   the brief/reference, not just "did it render".

## Install / auth (macOS)

```bash
curl -fsSL https://releases.rive.app/cli/install.sh | sh   # or: brew install --cask rive-app/tap/rive-cli
```
No login for local create/preview/verify/test/screenshot. `--publish` (incl.
`=web`), `--rev`, `rive push`, `rive pull` need `rive login`; web scripts need
signed output. (rive 1.2.0) `--publish=web` goes LIVE instantly, no confirm —
`--unpublish=web --yes` undoes it, `--list-published` shows where. Ask the
user before ANY remote/destructive op: push, pull (overwrites), publish/
unpublish, login/logout, installs/updates, or edits outside the project.

## Exit codes & modes

0 ok · 1 build errors · 2 bad flags/usage · 3 not logged in · 6 test failures · 7 retry.
Build/capture MODES (verify/once/publish/unpublish/list-published/test/
bench/screenshot/semantics/data-dump) are exclusive. --pointer/--touch/--key/
--gamepad/--advance REQUIRE a capture; --data/--viewport/--fit = config.
JSON requires a build mode; screenshot paths are CWD-relative.

`rive pull` overwrites linked project files (no merge; `--yes` skips the
confirm) — commit or inspect local changes first. `rive docs push` covers the
round trip.

## Authoring rules that bite silently

1. **Draw order is REVERSED: first-declared child paints IN FRONT.** List
   overlays first, backgrounds last.
2. **FontAsset is a ROOT element** (sibling of `<Artboard>`). Nested → all text
   invisible, zero diagnostics anywhere. Same for `DataConverter*`, `ViewModel`.
3. **Ids are numeric `client:object`** (`0:12`) — hex-ish ids (`0:8e`) are build
   errors. Unique across ALL .rml files (they compile as one document).
4. **Units**: rotation=radians (full turn 6.2831855) · `LinearAnimation.duration`
   =frames at fps=60 · `StateTransition.duration` =MILLISECONDS.
5. **Keyframes**: element type must match property type (`KeyFrameDouble` for
   double, `KeyFrameColor`…); mismatch = silent no-op. Default interpolation is
   `hold` (snap); put eases on the FIRST keyframe of a segment. `cubic` needs a
   `CubicEaseInterpolator x1 y1 x2 y2` — ONE shared artboard-level element
   referenced by `interpolatorId` from every keyframe beats per-keyframe
   children; it rejects a `name` attribute (build error) despite the schema.
   (rive 1.1.0) Keyed `TrimPath.start/end` builds green but NEVER applies from
   CLI RML (schema lies — draw-on via keyed pivot-node scaleX). (rive 1.4.0)
   `KeyedProperty` takes symbolic names (`property="rotation"`, what pull
   writes); unknown name = did-you-mean build error; numbers still compile.
6. **Text chain** (each link fails silently): `Text > TextStylePaint
   (fontAssetId→root FontAsset, needs Fill child) > TextValueRun (styleId)`.
7. **Colors**: ARGB hex, no `#`/`0x` (`FF57A5E0`). In rive.yaml, QUOTE them
   (`"#1D1D1D"`) or YAML eats the rest as a comment.
8. **SM layer boilerplate**: ≤1.2 needed Any+Exit+Entry or the layer didn't
   import; 1.3.0+ auto-adds missing Any/Exit (Entry-only layer verified green).
   Artboard needs `defaultStateMachineId` or binds/pointer are dead while
   timelines still play (looks alive, isn't).
9. **Keyed values are ABSOLUTE**: a timeline keying y/scale on a node FORCES that
   value, clobbering authored offsets. Never key offset wrappers — add a
   zero-offset inner node and key that.
10. Width/height live on the path (`Rectangle`/`Ellipse`), NOT on `Shape`.
11. Enum values are validated (use symbolic names); most other silent failures
    are not. Layout alignments: topLeft…bottomRight, center*, spaceBetween*.
12. `Component.flags` (hidden etc.) is editor-only — `hidden="true"` does NOT
    change rendering.
13. Misspelled VM/property names build clean (editor-only validation); use
    camelCase, no spaces, no Luau keywords.
14. `nameBased="true"` binds are inert in CLI-authored files (no ManifestAsset).
15. **Re-skinning artwork without touching animation**: keyed component ids ARE
   the contract — geometry/colors are free to change while ids survive (incl.
   keyed `Shape`s). Author static attrs to the f0 key values so rest pose
   matches. `Shape`s nest child `Shape`s: children paint in front of the
   parent's own path and ride its keyframes.

## Verified interaction patterns

**VM-bool toggle (click flips)**: one click listener whose `ListenerViewModelChange`
holds TWO `DataBindContext`s (read via root `DataConverterBooleanNegate` +
`converterId`; write back `direction="true"`) in one `BindablePropertyBoolean`.
SCHEMATIC XML in NOTES; mint fresh ids.

**Condition-guarded transitions need BOTH comparators**: property comparator
AND `TransitionValueBooleanComparator value="true"` — else the condition
never fires while verify stays green. XML in NOTES; `duration` is in ms.

**Press-and-hold (PTT)**: `down` listener on the button writes literal `true`
(`propertyValue="true"` + `direction="true"` bind); `up` listener on the
**ARTBOARD** writes `false` (release anywhere ends it — face-only `up` sticks).

**One-shot intro + looping hold**: intro timeline (no loopValue) chains to the
loop via `<StateTransition enableExitTime="true" exitTimeIsPercetange="true"
exitTime="100" …/>` — NOTE THE TYPO (the format's own spelling; the correct
one is rejected). Loop re-pins intro end values (icon=0); idle restores (1).
Icon morph: two groups at one anchor, scale 1↔0 with overshoot eases.

**Keyframe/pointer proof** (artboard-space coords; interactions run in written order):
```bash
rive . --screenshot=rest.png --advance=1
rive . --screenshot=on.png  --pointer=click@X,Y --advance=20
rive . --screenshot=off.png --pointer=click@X,Y --advance=1 --pointer=move@400,400 --pointer=click@X,Y --advance=20
rive . --data-dump=- --pointer=click@X,Y   # prints VM state ("changed": true)
```
Separator between two clicks on the same listener: MANDATORY ≤1.3 (1.4.0 fixed
*transitions* seeing listener writes same-frame; listener→listener untested) — keep it.
Ripples/wave effects: opacity-0 gradient-stroke ellipses keyed scale+opacity,
staggered; drag: `--pointer='drag@x1,y1>x2,y2:12'` (QUOTE it). Also available:
`--key=name[:down|repeat|up]`, `--gamepad=button@west:down`, `--data=path=value`,
`--viewport=WxH` (responsiveness proof), `--fit=contain`, `--touch=tap@x,y`
(per-finger ids; chained drags = pinch), `--pointer=wheel@x,y:dx,dy` /
`trackpad@…` (unconsumed scroll now LOGS `wheel: nothing at X,Y scrolled`).

## Luau scripts

- Attach: `<ScriptedLayout scriptAssetId="…">` in RML + `<ScriptAsset file="…"
  name="…" id="…"/>` at root. Modules need `isModule="true"`.
  Rive 1.1.1 resolves modules even when declared after importers; earlier
  versions needed modules first or `require` failed at runtime.
- Generator shape is a CONTRACT (rive 1.4.0): `return function(...): <Proto><T>`
  annotated with the `Scripted*` element's protocol (Layout/Node/PathEffect/
  Converter/ListenerAction/TransitionCondition/Interpolator) — LOAD-BEARING:
  drop it and `--verify` stays green while the script NEVER runs (only hint:
  raw untimestamped `ScriptAsset doesn't have a generator function <name>` ×2;
  live-verified on Layout, other protocols expected-untested).
- `Input<T>` is a TYPE ANNOTATION only: return plain defaults (`speed = 1`);
  RML `ScriptInput*` injects by NAME (mismatches are silent).
- Strict type-check fails the build: annotate every param; protocol state
  needs a named `type` + exact table literal; `advance` returns boolean.
- Lifecycle: `init(self, context)` (may run twice — guard VM/input access),
  `resize(self, size, scale)` (3rd param = DPR; size canvases by it),
  `advance(self, seconds)`, `draw(self, renderer)`.
- Text in scripts: NONE in ≤1.2 (Font opaque — UI belonged in RML); 1.3.0+
  shapes and draws it (`context:font`, `Text:append`, `text:draw` — covered by
  `rive docs luau/api/text`; samples `scripted_text`, `text_*`).
- No io/coroutine/debug — net is `fetch(url)` (Promise<Response>), needs
  `--allow-net` (rive 1.4.0) else rejects `disabled`. `print` → stderr + `logs.file`.
- Tests: `*_test.luau` with `return function(): Tests return setup end`;
  `test.group('name', fn)`, `test.case('…', fn(expect))`,
  `expect(x).is(y) / .greaterThanOrEqual(y) / .lessThan(y)`. Run `rive . --test`
  (exit 6 on failure; JSON: passed/failed/failures[{test,line,message}]).

## rive.yaml essentials

```yaml
name: proj          # only required key
main: scene         # default artboard
artboard: {width: 800, height: 600, background: "#1D1D1D"}  # script-only projects
output: {dir: build}
logs: {file: build/rive.log, problems: build/problems.log}  # problems.log = one build per rewrite
exclude: [docs]     # globs: * crosses /, ? one char
```
Script-only project = no .rml at all (`main:` + `artboard:` block).
File discovery: `.rml` scene markup · `.luau` scripts · `.wgsl` shaders ·
png/jpg/webp images · anything else = blob asset. Assets embed only when
referenced; scripts/shaders always compile.
Multi-artboard files: give each root `<Artboard>` distinct x/y on the Editor
stage (and SM graph states distinct x/y). Do not move child nodes to fix overlap.

## Reverse-engineering a bare .riv

Only geometry survives import. Best edit path: Editor `.rev` export →
`rive create dir --from-rev=f.rev` (animations kept). Else parse the binary
(docs wrong on ToC words, bool=1 byte, parentId drift — pair by STREAM ORDER;
full wire-format notes in NOTES.md) or render via @rive-app/canvas locally.

## Flutter runtime pairing (verified vs rive CLI 1.1.0)

0.14 has NO `RiveAnimation`; 0.13 can't load CLI 1.x `.riv`. Loader chain +
`riveFactory:`, `rive_native:setup` before `flutter test`, VM-trigger and
`Feather` traps — full details in NOTES.md (Flutter runtime pairing).

## Debug ladder (when something doesn't show/move)

1. Screenshot at `--advance=1` (rest pose lies).
2. Scripted project: grep stderr + `logs.file` for `console` / `generator
   function` even on exit 0 — scripts can fail to RUN with a green build.
3. Literal probe: set bound text to `LITERAL-HERE` — if it renders, the bind is
   dead (usually missing state machine or wrong property on target element).
4. Number probe: bind to opacity instead — changes at all? path vs converter.
5. `strings build/x.riv | grep Name` — it's in inspect but did it EXPORT?
6. Missing asset file (`file="NoSuch.ttf"`) = zero diagnostics; check disk.
7. Keyboard needs `FocusData` on the target; keyPhase 7 = both edges (menu
   skips rows). `--data` loses to two-way binds — `sourceToTargetRunsFirst="true"`.

## Evolution protocol (self-maintaining — read before editing this skill)

This skill improves as agents work with Rive. The gate below is the spam
filter; **when in doubt, don't add to SKILL.md** — append to NOTES.md instead
or add nothing. Forgetting a marginal fact is cheap; diluting this file is not.

**Add a rule to SKILL.md only if ALL four pass:**
1. **VERIFIED live** — you ran the command and observed the result this session.
   No doc quotes, no theories, no "should work".
2. **REUSABLE** — true in any project, not just the one you're in. No ids,
   colors, art specifics, or project layout.
3. **NON-OBVIOUS** — not findable via `rive docs <topic>` / `rive schema` /
   the generated AGENTS.md — OR it *contradicts* them (doc drift is the single
   most valuable category; always record the version).
4. **WORTH IT** — it cost real debugging time, caused a silent failure, or a
   green-but-wrong build. Trivia that costs nothing to rediscover stays out.

**Where things go:**
- `SKILL.md` — the one-line rule (+ minimal code block only when exact syntax
  matters, e.g. the `exitTimeIsPercetange` typo). Hard budget: ≤250 lines;
  over? Compress a section into NOTES.md, keep the one-liner.
- `NOTES.md` — dated append-only journal: commands, evidence, full patterns.
- `CLI_REFERENCE.md` — CLI flags/behavior/exit-code facts only.
- `CHANGELOG.md` — one line per SKILL.md edit (date · what · rive version).

**Before writing:** search all four files; refine existing rules before adding.
**Conflicts:** live evidence beats docs. If a rule is version-dependent, mark
it `(rive X.Y …)` rather than deleting — old versions don't disappear.
**After editing SKILL.md:** append the CHANGELOG line and, if you verified on
a new CLI version, update the "Verified against" line at the top.
**Never add:** session narratives, unverified guesses, project-specific markup,
anything one `rive docs` lookup away, or restatements of AGENTS.md.
