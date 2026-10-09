# Rive Skill Notes — everything NOT in the generated AGENTS.md

> **Journal rules** (see Evolution protocol in SKILL.md): append-only, dated
> entries. Format: `## N. TITLE — RESULT (YYYY-MM-DD, rive X.Y)` then commands,
> evidence, context. Full detail belongs here; SKILL.md keeps only the
> distilled rule. Verify before writing; grep for duplicates first.
>
> **Historical evidence notice:** entries describe the CLI version used at the
> time — they are NOT necessarily current recommendations. Prefer SKILL.md for
> active rules; for CLI behavior prefer the newest applicable CLI_REFERENCE
> section (§16 = 1.2.0, §17 = 1.3.0, §18 = 1.4.0); verify uncertain behavior
> against the installed CLI.

Goal: feed a future global skill (e.g. `~/.agents/skills/rive/SKILL.md`).
Scope: knowledge an agent needs that the project-generated `AGENTS.md` does NOT give it.

## What the generated AGENTS.md ALREADY covers (do not duplicate in skill)
- "Prefer `rive docs` / `rive schema` over memory; never guess a type or property"
- `rive schema <Type>` / `--search`, `rive docs --list` / `<topic>`
- After every edit: `rive . --verify` (exit + `--format=json`), `rive inspect . --summary`
- "Clean verify/inspect is not enough — read what got built"
- `rive . --screenshot --advance=1` for visual checks
- Work autonomously, reasonable defaults for details

So the skill's added value must be: **workflow mechanics, authoring conventions, silent-failure
traps, property keys, flag semantics, exit codes, JSON parsing, script/test patterns** — the
things that otherwise cost debugging time.

---

## 1. Verified CLI mechanics (live, rive 1.0.3 macOS arm64)

- Exit codes: 0 ok; 1 build errors; 2 bad flag values / flag misuse; 3 not logged in;
  6 test failures; 7 service unreachable.
- Build modes are mutually exclusive: `--verify | --once | --publish | --test |
  --screenshot | --semantics | --data-dump | --bench`. Combining two → exit 2.
  (NOTE: `--data-dump` and `--semantics` ARE modes, unlike web docs which describe
  `--data-dump` as a modifier.)
- Unknown flags: exit 2 in 1.0.3 (docs claim silently ignored — outdated).
- `--format=json` requires a build mode; JSON on **stdout**, all logs on **stderr**
  (compiler errors too — never `2>/dev/null` while debugging).
- Bench stats print to stderr.
- Screenshot paths are **CWD-relative**; parent dir must exist or only
  `screenshot failed: <path>` (stderr).
- `--advance` accepts frames (`30`), time (`1s`, `250ms`, decimals `1.5s`=90 frames);
  works with `--screenshot`, `--semantics`, `--data-dump`; interactions run in written order.
- `--pointer` kinds: down/up/move/click + `drag@x1,y1>x2,y2:steps` (quote in shell!).
  Coordinates are artboard-space. Put `--advance` between two clicks on the same
  listener (a listener's write isn't visible to the next until a frame passes).
- `--data=path=value` — property path relative to artboard-bound VM instance,
  segments are property names (`settings/speed=10`). Mismatched path = stderr note
  `data: no property at "<path>"`, dropped, build still succeeds.
- `--data-dump=-` dumps VM JSON to stdout; `--data-dump-filter='*'` or `battery/*,score`.
- `--artboard=<name>`: wrong name silently falls back to first artboard.
- `rive create` also writes `CLAUDE.md` (imports AGENTS.md). `rive push` EXISTS in 1.0.3.
- `rive doctor` exit 0 unless a check fails; not-logged-in is only a warning.
- `--quiet` hides even compiler errors — parse JSON or read `logs.problems` instead.
- Env: `RIVE_NO_TUI=1` forces list output everywhere (pickers draw on stderr);
  `RIVE_ANALYTICS=off`; `TERM=dumb` also disables pickers.

## 2. Authoring conventions & silent-failure traps (the big ones)

1. **FontAsset must be ROOT element** (sibling of `<Artboard>`). Nested inside the
   artboard → all text invisible, zero problems reported, inspect clean.
2. **Draw order: first-declared child paints IN FRONT** (front-to-back listing).
   Backgrounds go LAST.
3. Duplicate ids anywhere in a document (all .rml files compile as ONE document) →
   hard error exit 1. Ids look like `0:N`; pick unique Ns; keep an id map.
4. Text chain (each link fails silently, none appear in problems):
   `Text > TextStylePaint(fontAssetId→root FontAsset, needs Fill child) >
   TextValueRun(styleId→the paint)`. Cross-reference ids by hand or via inspect.
5. Number VM property CANNOT drive text run (no number→string converter exists;
   `DataConverterToNumber` is the wrong direction). Use `ViewModelPropertyString`
   bound to run's `text` (propertyKey 268).
6. Keyframe element type must match property type (`KeyFrameDouble` for double,
   `KeyFrameColor`, `KeyFrameBool`, `KeyFrameUint`, `KeyFrameString`, `KeyFrameId`,
   `KeyFrameCallback`); mismatch = silent no-animation at runtime, clean build.
7. `interpolationType` default is `hold` (snap); eased segments need
   `linear`/`cubic` on the FIRST keyframe of each segment (last keyframe's
   interpolation never read).
8. Colors: ARGB hex, no `#`, no `0x` (`FF57A5E0`), everywhere — RML attributes and
   `ViewModelInstanceColor propertyValue`.
9. State machine layers REQUIRE `AnyState`, `ExitState`, `EntryState` (even unused)
   or the layer does not import.
10. In rive.yaml, `background: "#1D1D1D"` must be QUOTED (YAML comment otherwise).
11. Empty project preview = dark rectangle (not a failure).
12. Editor-only properties (e.g. `defaultInstanceId`, `exports`, `viewModelInstanceId`)
    are authorable but hidden from `rive schema` unless `--all`.

## 3. Property keys seen in the wild (verify with `rive schema <Type>` before use)
- Node/Transform: x=13, y=14, rotation=15
- TextValueRun.text = 268
- Width keying etc: get from `rive schema <Type> --animatable`

## 4. Screenshots/verification workflow that works
- `rive . --verify --format=json` → parse `data.problems` (line/column ZERO-based in
  JSON; one-based in terminal/inspect).
- `rive inspect . --summary` → object counts per type per artboard + problems.
- Visual: `rive . --screenshot=path --advance=1` (never 0 — 0/rest pose is authored
  rest, not the playing animation).
- Toggle proof pattern: rest → click+advance20 → click,advance1,click,advance20.

---
---

# EXPERIMENT LOG (new findings appended below as they happen)

## 5. EXPERIMENT: layout + click-toggle state machine (togglelab/) — SUCCESS
The canonical interactive pattern (distilled from integrated_titlebar sample, verified live):
```
VM Boolean ── click listener flips it ── two AnimationStates switch via
condition-guarded transitions ── each state plays a timeline that keys the knob x
```
Exact markup fragments that work:
- Listener toggle (read via negate converter, write back two-way):
  ```xml
  <StateMachineListenerSingle targetId="<buttonId>" listenerTypeValue="click">
    <ListenerViewModelChange fromViewModelProperty="true" fromDataBindId="0:55">
      <BindablePropertyBoolean>
        <DataBindContext sourcePathIds="<vm>-<prop>" propertyKey="634" id="0:55" converterId="0:98"/>
        <DataBindContext sourcePathIds="<vm>-<prop>" propertyKey="634" direction="true"/>
      </BindablePropertyBoolean>
    </ListenerViewModelChange>
  </StateMachineListenerSingle>
  ...
  <DataConverterBooleanNegate name="Not" id="0:98"/>   <!-- root level -->
  ```
- Condition-guarded transition — **needs BOTH comparators** (missing the value
  comparator = condition silently never true; knob never moves, verify clean!):
  ```xml
  <StateTransition stateToId="..." duration="12">   <!-- ms! -->
    <TransitionViewModelCondition>
      <TransitionPropertyViewModelComparator>
        <BindablePropertyBoolean>
          <DataBindContext sourcePathIds="vm-prop" propertyKey="634"/>
        </BindablePropertyBoolean>
      </TransitionPropertyViewModelComparator>
      <TransitionValueBooleanComparator value="true"/>   <!-- REQUIRED -->
    </TransitionViewModelCondition>
  </StateTransition>
  ```
- Proof commands (button centered at 250,250 in a 500x500 artboard):
  `--screenshot rest --advance=1` → `--pointer=click@250,250 --advance=20` (on)
  → `--pointer=click@250,250 --advance=1 --pointer=click@250,250 --advance=20` (off=rest).
  Plus `--data-dump=- --pointer=click@250,250` prints `"on": true, "changed": true`.

## 6. Trap confirmations hit live (again)
- `Shape` has no `width`/`height` attributes — hard error names them (good).
- Enum values are validated with the accepted list in the error: layoutAlignmentType
  accepts topLeft|topCenter|topRight|centerLeft|**center**|centerRight|bottomLeft|
  bottomCenter|bottomRight|spaceBetweenStart|spaceBetweenCenter|spaceBetweenEnd
  (there is NO centerCenter — use `center`).
- Layout styles: `flexDirectionValue="row|column"`, `layoutWidthScaleType/`
  `layoutHeightScaleType="fixed|fill|hug"`, `gapHorizontal/gapVertical` +
  `*UnitsValue="points"`, alignment via single combined enum (above).
- Listeners can target a LayoutComponent (targetId) — clicks land on children too.
- Single-keyframe timeline + cubic interpolator child worked first try:
  `<KeyFrameDouble value="40" interpolationType="cubic"><CubicEaseInterpolator
  x1="0.2" y1="0" x2="0.2" y2="1"/></KeyFrameDouble>`.

## 7. EXPERIMENT: Luau scripting (scriptlab/) — SUCCESS after 3 real traps
Working setup: RML box with `ScriptedLayout` + `ScriptInputNumber`s → bars.luau
(Layout protocol) → requires wave.luau (pure module) → wave_test.luau (Tests).

### Script input binding (NONE of this is in AGENTS.md)
- `Input<T>` is a TYPE ANNOTATION ONLY. In the returned table provide the plain
  default value: `barCount = 8` (NOT Input.new, NOT `.value` access).
- Runtime injects RML `ScriptInput*` values onto those fields BY NAME.
  `type X = { speed: Input<number> }` ↔ `<ScriptInputNumber name="speed" .../>`.
- Annotating `Input<number>?` forces nil-guards everywhere in strict mode;
  prefer non-optional + defaults in the table.
- Strict Luau type-check FAILS THE BUILD: annotate every function param;
  unknown globals and nil-arithmetic are build errors (exit 1).
- VM inputs differ: `Input<Data.Settings>?` + `settings.speed.value` (optional,
  nil until second init — see pointer_reactive track.luau).

### Modules / require — the big one
`require('wave')` from a scene script FAILS AT RUNTIME (script keeps running,
effect silently missing!) unless the module is declared as a ScriptAsset
**with `isModule="true"`**, declared **BEFORE** the importing script:
```xml
<ScriptAsset file="wave.luau" name="wave" id="0:81" isModule="true"/>
<ScriptAsset file="bars.luau" name="bars" id="0:80"/>
```
- Error surfaces ONLY as a runtime console line: `console :0  bars:4: require
  could not find a script named wave` (stderr + rive.log). Build stays green.
- `folderPath="widgets"` namespaces the require path: `require('widgets/button')`.
- Tests (`*_test.luau`) require modules by FILE name and work without
  ScriptAsset declaration (test context resolves files; scene context doesn't).

### Tests protocol (verified)
```luau
local wave = require('wave')
function setup(test: Tester)
    test.group('bar', function()
        test.case('phase 0 starts at midpoint', function(expect)
            expect(wave.bar(1, 12, 0)).is(0.5)
        end)
    end)
end
return function(): Tests return setup end
```
- Expectations seen: `.is()`, `.greaterThanOrEqual()`, `.lessThanOrEqual()`,
  `.lessThan()`. Run: `rive <dir> --test` (exit 6 on failure, JSON has
  passed/failed/failures[{test,line,message}]).
- Tests run even when the SCENE build fails — JSON reports test results AND
  build errors separately (overall exit 1, passed:3 present).

### Runtime observation
- `print` → stderr console lines (`console bars:21  <msg>`) + appended to
  `logs.file` (build/rive.log) interleaved with build/system messages.
- Runtime script errors log as `console :0 <file>:<line> <msg>` — NOT build
  problems; a screenshot can succeed with the scripted part missing.
- init prints ran ONCE per run in a no-VM script; the "init runs twice" quirk
  (pointer_reactive) applies when script/VM INPUTS are involved — first init
  has inputs/VM absent, guard with nil checks.
- At init time `resize` hasn't run: size prints 0x0.
- Layout protocol lifecycle that worked: init/resize(size, scale)/advance/
  draw(renderer); Path:reset/moveTo/lineTo/close; Paint.with({color=Color.rgb(
  r,g,b)}); renderer:drawPath(path, paint). Draw order inside a LayoutComponent:
  earlier siblings on top (same rule as artboard children).

### Script-only projects (no RML at all — hello_rive sample)
```yaml
name: hello_rive
main: main              # entry script
artboard:
  width: 800
  height: 600
  background: "#1D1D1D"
```

## 8. EXPERIMENT: multi-file RML (togglelab split) — SUCCESS
- Moved `<DataConverterBooleanNegate>` + `<ViewModel>` block out of scene.rml
  into `vm.rml`; cross-file id references (0:50/0:51/0:98) resolve fine,
  click-toggle still works after the split.
- All .rml files compile as ONE document: ids unique across ALL files,
  order between files matters only for module ScriptAssets.

## 9. EXPERIMENT: extra flags & integrations (all live-verified)
- `--semantics` — own build mode; writes `build/<name>.semantics.json`
  (a11y tree: {"schema":1,"artboard":"...","roots":[...]}). Empty when no
  semantic nodes authored.
- Interaction flags require a capture mode: `--pointer, --gamepad, --key,
  --semantic-action and --advance need --screenshot, --semantics or
  --data-dump` (exit 2). So `--key`/`--gamepad`/`--semantic-action` all exist.
- `--key=<name>[:phase[+mods]]` — phase down/repeat/up; bare name = whole
  keystroke. One keystroke must move a menu exactly one row (phase-mask bug
  detector). Keys reach only the focused node; headless starts unfocused.
- `--gamepad=axis@leftX:-0.9`, `button@west:down|:up` or analog `:0.5`,
  `connect`/`disconnect`. W3C names; bare index is W3C 0-based but Luau
  changeIndex is +1. Pad connects implicitly on first event.
- `rive lsp` — JSON-RPC over stdio (LSP). Capabilities: sync, formatting,
  definition, hover, completion (triggers `. : " / @`), semantic tokens.
  Framing: standard Content-Length headers.
- `--serve`/`--headless-serve` — listens on TCP 9640 (live-link protocol for
  connected players; NOT http). `--serve=<port>` to change.
- `--debug[=port]` — DAP debug server, default 9641, loopback only; VS Code
  Rive extension attaches. Rebuilds keep the session.
- `--fit=<mode>` — fill/contain/cover/fit-width/fit-height/none/scale-down;
  works with --screenshot/--semantics; default viewer fit is `layout`
  (artboard resizes to window = responsive check by dragging).
- Auth gates verified: `whoami`/`--publish`/`--rev` unsigned → exit 3.
- rive.yaml window integration (macOS only): `window: {titleBar: integrated,
  controls: {x,y}, dragHeight: N}` (integrated_titlebar sample).

## 10. Docs-distilled workflow knowledge (from `rive docs workflow`+`gotchas`)
CRITICAL for skill — these are the highest-value items (AGENTS.md says nothing about them):
- Build in PASSES: wireframe (every box a FILLED box, sized fixed/fill — hug
  with no children = zero size) → structure → content → detail. Verify+shoot
  every pass; object count must go UP each pass:
  `rive inspect <dir> --json | jq '[..|objects]|length'`
- rive REWRITES your RML on first build: writes id= onto every element that
  lacked one. First diff touches everything; commit it alone.
- inspect shows authored RML, NOT what shipped in the .riv; export gaps exist.
  When wired-correct-but-inert: `rive <dir> --once && strings -n 3
  build/<name>.riv | grep -c <Name>`.
- --verify re-imports the riv in memory ("would fail to load" = build error).
- Rotations RADIANS (full turn 6.2831855); LinearAnimation.duration FRAMES
  (fps=60); StateTransition.duration MILLISECONDS. (Three different units!)
- interpolationType default = hold (snap!). Put the ease on the FIRST keyframe
  of a segment; the last keyframe's interpolation is never read. cubic needs a
  CubicEaseInterpolator child (x1,y1,x2,y2 in 0..1).
- No-state-machine artboard = half alive: binds inert, pointer dead, but first
  timeline still plays (looks alive!). Probe: author unmistakable literal text
  ("LITERAL-HERE") on a bound run and render.
- Probe suspect binds with a NUMBER property (opacity), never a string.
- Every listener under the pointer FIRES (no occlusion unless isTargetOpaque);
  transparent fills are hit-testable; two listeners writing one property fight.
- Keyboard listeners need FocusData child on the target; keyPhase bitmask
  1=down 2=repeat 4=up (7 = both edges of a keystroke → menu skips 2 rows).
- Missing asset file (FontAsset file=NoSuch.ttf) = ZERO diagnostics anywhere;
  check disk: grep -oh 'file="[^"]*"' *.rml | while read f; [ -e $f ]...
- --data loses to a two-way bind (direction="true") on the same property;
  fix = sourceToTargetRunsFirst="true" on the DataBindContext.
- VM/property naming checked only by the EDITOR (camelCase, no spaces, no Luau
  keywords); CLI builds garbage names clean.
- Give SM states + multiple artboards distinct x/y (editor canvas overlap).
- Component.flags (hidden/locked/etc.) is editor state only — hidden="true"
  does NOT change rendering. Write bits as separate boolean attributes.
- Feather in a Fill renders nothing (Stroke only). resize(self,size,SCALE)
  3rd param: size canvases by scale or get 2x-blurry on Retina (@1x screenshots
  can't catch this; live window shows @2x).
- Cross-axis fill in a wrap container collapses to zero height (flex
  alignContent gap).
- wrap+fill landmines in wireframe pass; give one child fixed/hug height.
- listenerTypeValue values: enter exit down up move event click
  componentProvided textInput dragStart dragEnd viewModel drag focus blur
  keyboard semanticAction gamepad.
- Text sizingValue="fixed" needed on Text inside layouts (titlebar sample).
- ScriptedPathEffect/ScriptedDrawable = effects WITHOUT taking over the scene;
  no text API in scripts (Font opaque) — build UI in RML, compute in scripts.
- Available Luau stdlib: math table string os utf8 buffer bit32 + base. NO io,
  coroutine, debug.

---

# 11. ARCHIVED PROPOSAL — proposed SKILL.md structure (2026-09-16, superseded)

> **Archived:** this proposal predates the live skill. The actual, current skill
> is `~/.agents/skills/rive/SKILL.md` — do not follow the structure below.

```markdown
---
name: rive
description: Build, verify, and test Rive graphics (.riv) with the Rive CLI —
  RML scenes, Luau scripts, view-model data binding, state machines, headless
  screenshots/pointer/data-driven verification. Use when the user mentions
  Rive, RML, .riv files, rive CLI, or Rive animation/graphics work.
---

## Core loop (every project, AGENTS.md won't say this)
1. rive create <dir> → read generated AGENTS.md
2. Lookups FIRST: rive schema <Type> (--animatable/--bindable/--all/--json),
   rive docs <topic> — never guess names. Topics that matter most:
   workflow gotchas format data state-machines layout text luau/protocols
3. Author in PASSES (wireframe with FILLED boxes → structure → content →
   detail); after each pass: --verify --format=json, screenshot --advance=1,
   object count via inspect --json | jq '[..|objects]|length'
4. Interaction proof: rest/on/off triple with --pointer=click@x,y --advance=20
   (separator between clicks on same target!)
5. Scripts: strict Luau; annotate every param; modules need isModule=true
   ScriptAsset declared FIRST; tests in *_test.luau run with --test
6. Ship: --once (unsigned, unwatermarked) / --publish (signed, needs login)

## Authoring rules (RML)
- first-declared child paints IN FRONT; FontAsset + converters + VMs at root
- ids 0:N unique across ALL .rml files (one document)
- units: rotation=radians, duration=frames@60fps, transition duration=ms
- keyframes: type must match property; default interpolation=hold; ease on
  first keyframe of segment; cubic needs interpolator child
- text chain: Text > TextStylePaint(fontAssetId, Fill child) > TextValueRun
  (styleId) — every link silent
- SM layer needs AnyState+ExitState+EntryState; artboard needs
  defaultStateMachineId or binds/pointer are dead
- listener+VM toggle pattern & condition needs TransitionValueBooleanComparator

## Verification matrix
| check | proves | blind to |
|--|--|--|
| --verify --format=json | compiles + would load | everything runtime |
| --test (exit 6) | script behavior | non-test scenes |
| --screenshot --advance=1 | appearance | nothing |
| inspect --summary/--json | structure, bind paths | runtime, export gaps |
| --data-dump=- | VM state end-to-end | visuals |
| strings build/x.riv | shipped in bytes | — (export-gap check) |

## Silent failures checklist (query recipes in gotchas doc)
FontAsset nested / missing asset file / no state machine / dead bind property
on wrong element / keyframe type mismatch / no value comparator / script
input name mismatch / require without isModule / cubic without interpolator /
--data vs two-way bind / hidden flag doing nothing

## CLI quick reference
- modes (pick ONE): --verify --once --publish --test --screenshot
  --semantics --data-dump --bench
- capture modifiers: --viewport=WxH --fit=mode --advance=N|Ns|Nms
- interactions (need a capture): --pointer=click@x,y 'drag@x,y>x,y:steps'
  --key=name[:phase] --gamepad=... --data=path=value
- exits: 0 ok · 1 build · 2 usage · 3 auth · 6 tests · 7 retry
- JSON: stdout, zero-based lines; logs/errors: stderr
- env: RIVE_NO_TUI=1 RIVE_ANALYTICS=off TERM=dumb
```

## Where the reference material lives (for skill maintenance)
- RIVE_CLI_AGENT_GUIDE.md — full CLI reference + doc-drift corrections (§15)
- This file — authoring traps + verified patterns + experiments
- Working examples in this workspace: togglelab (VM-bool toggle + conditions),
  scriptlab (ScriptedLayout + inputs + module + tests), weathercard (text +
  data bind + timeline), plus 10 samples under `rive samples --path`

## 12. EXPERIMENT: press-to-talk button (ptt/) — SUCCESS, new patterns
- **Press-and-hold (not toggle)**: two listeners write LITERAL values, not toggles:
  down → `BindablePropertyBoolean propertyValue="true"` + direction="true" bind;
  up → propertyValue="false". Headless proof: `--pointer=down@x,y --advance=N`
  (no up = still holding); release adds `--pointer=up@x,y --advance=N`.
- **Ripple effect** (no code): backmost ellipse STROKES with gradient paint,
  opacity 0 at rest; talk timeline keys scale 1→1.55 + opacity .85→0 over the
  loop, second ripple staggered by half the loop (frame 27/54, with an extra
  hold keyframe at frame 0/27 to keep it dark before its turn).
- **Mic cradle (open U)**: PointsPath isClosed="false" + 3 CubicMirroredVertex
  (side vertices rotation=90, bottom rotation=0); Stroke cap/join="round".
  Mic stand = 2 StraightVertex open path + round cap.
- **Gradient STROKES work** on parametric + points paths (LinearGradient child
  of Stroke, coordinates in shape-local space). Rings/outlines in brand
  gradients are cheap this way.
- **Eased loop breathing**: key scale (16=X, 17=Y, 18=opacity on Shape/Node)
  1→1.025→1 with cubic interpolators on the outgoing keyframes.
- Scale/rotation about a center: put Node at center coords, children centered
  via originX/Y=0.5 — scale keys on the Node.

## 13. EXPERIMENT: PTT v2 — icon morph (mic -> 3 dots) + polish — SUCCESS
- **Icon morph without path interpolation**: two Groups at the same anchor.
  Talk timeline: group A scale 1→0 (ease-in-ish cubic (0.55,0)-(0.7,0.5)),
  group B 0→1.15→1 (overshoot, back-out cubic). Idle timeline MUST key the
  restore values at frame 0 (A=1, B=0) or the morph never reverses.
- **Staggered dot wave**: per-dot opacity keyframes, phase offsets 0/9/18
  frames, period 27 over a 54-frame loop; loop-wrap continuity comes free when
  each dot's last key value matches its phase pattern (wrap interpolates from
  frame 54 to first key).
- **Squash & stretch**: scaleX/scaleY keyed independently (1.07/0.90 at press,
  settle 0.965, micro-pulse) — the cartoon principle that sells "press".
- **Soft glow**: wide (thickness 26) low-opacity gradient stroke ellipse
  behind everything; opacity keyed 0.1 idle / 0.3 talking.
- Smoothness kit: symmetric cubic (0.37,0)-(0.63,1) for breathing; back-out
  (0.3,0)-(0.15,1) for the initial press snap; ease-out (0.1,0.6)-(0.2,1)
  for ripples. Transition durations 90ms in / 300ms out (blend does the rest).
- TRAP confirmed: id must be numeric "client:object" (`0:12`); `0:91p` →
  build error listing every offender.
- TRAP (self-inflicted but common): mismatched KeyFrameDouble/
  CubicEaseInterpolator close tags — error names the OPEN tag's line only.

## 14. PTT v3 — three production bugs fixed (big skill lessons)
1. **One-shot intro inside a LOOPING timeline replays every wrap** (icon
   reappeared cyclically). Fix = split states: Intro (no loopValue, plays once
   and holds) -> Loop via exit-time chaining:
   `<StateTransition stateToId=... enableExitTime="true"
    exitTimeIsPercetange="true" exitTime="100" duration="80"/>`
   NOTE THE TYPO: `exitTimeIsPercetange` is the format's own spelling — the
   correct spelling is REJECTED. Also add a condition release path from the
   intro state itself (quick taps skip the loop).
   The Loop timeline must re-pin the intro's end values (mic=0, dots=1) so
   they hold forever; Idle re-pins the restore values (mic=1, dots=0).
2. **PTT release must be artboard-level**: an `up` listener on the button face
   never fires when the pointer drifts off / releases outside → stuck talking.
   Pattern: down on the button target, up on the ARTBOARD id (contains all).
3. **Expanding-ring ripples read cheap**; a single wide low-opacity gradient
   STROKE ellipse behind everything, scale+opacity-pulsing, looks better and
   costs less.

## 15. REVERSE-ENGINEERING A BARE .riv (spielg.riv) — decoded successfully
### What a .riv contains (and not)
NO original SVG/vector source: only converted path geometry, paints, bones,
animations. Original SVG is NOT recoverable byte-for-byte; geometry-equivalent
SVG IS (see riv_parse.py + gen_svg.py in rive_test/).

### Wire format (verified against rive-runtime sources; the docs page is WRONG on 3 points)
- Header: "RIVE" magic, varuint major, varuint minor, varuint fileId
- ToC: varuint property keys until 0, then 2-bit wire types packed in
  **uint32 words (4 bytes per 4 properties)** — NOT bit-packed bytes (docs wrong)
- Objects: varuint typeKey, then (varuint propKey, value)... until propKey 0
- Wire value encodings (from core field type sources):
  * float/double = 4-byte float32
  * bool = 1 BYTE (docs wrong: says uint-sized)
  * uint/uint8/uint16/enum/Id = LEB128 VARUINT (docs wrong: says 4 bytes)
  * color = uint32 AARRGGBB (alpha in the TOP byte)
  * String = VARUINT length + utf8 (docs wrong: says uint32 length)
  * Bytes (blob assets, List<Id>) = varuint length + raw
- parentId = flat index of parent within artboard objects; index space DRIFTS
  vs object order (some objects don't consume slots) — match paints to shapes
  by STREAM ORDER (k-th distinct paint-parent ↔ k-th shape), not by raw seq.

### What's inside spielg.riv (decoded 2068 objects)
Character mascot 'spielg(1)' 1800x2177 for the who_made_this_movie Flutter game:
- 62 paths (1056 cubic + 128 straight vertices), 59 shapes, 64 solid colors
- 3 bone chains (RootBone+Bone) — skeletal animation
- 11 timelines: hint(10f) bave(60) shaking(5) l0/l1/l2(50) l3(60) clap(50)
  arm_left(60) head_movement(60) blink(120); 1 state machine 'idle'
- lifes_left number input drives 1D blend states (BlendState1D + l0-l3 blend
  anims + TransitionNumberCondition) = character degrades as lives are lost
- start_clap trigger -> clap timeline -> fires 'claping' event (app plays
  clap.mp3); 'click' trigger; view model 'hint'/'score' strings (text runs)
- 2 embedded assets: Intel One Mono font (~151KB) + claper-board graphic

### Tooling built (reusable)
- riv_defs.json — 352 type defs from `rive schema <Type> --all --json`
- riv_parse.py — full .riv -> JSON scene parser (spielg_scene.json)
- gen_svg.py — scene -> rest-pose SVG (spielg_rest.svg, 54 paths)
- view_spielg.html — browser render via @rive-app/canvas 2.42.1
  (WASM must be served locally: patch unpkg URL -> ./rive.wasm)

### Editing options for a .riv without its source
1. BEST: export .rev from Rive Editor -> `rive create <dir> --from-rev=x.rev`
   -> fully editable RML project (animations preserved)
2. Rebuild RML from extracted geometry (static art only; animations/skeleton lost)
3. Binary-patch colors/simple props in the .riv (fragile, version-dependent)

## 16. COMPLEX-OBJECT ANIMATION — director rebuild (authoring on extracted art)
- **Decision**: reverse-engineering the original's skeletal pose (Bone tips +
  weights) to rebuild it byte-faithfully is a rabbit hole; instead rebuild the
  character as clean structured RML (groups: Head pivot / Body / Clapper /
  Bubble) using the extracted palette + layout, then author NEW animations.
- New "action" animation authored end-to-end: one-shot 90f timeline —
  anticipation (bar opens -0.5rad, head tilts back) → SNAP (bar 0 in 7 frames,
  hard ease) → hop (-46px) → bubble pop (scale overshoot 1.12) → settle.
  State machine: Idle →(VM bool true)→ Action →(exitTime 100% + bool false)→
  Idle. Press on hit-area, release ANYWHERE (artboard-level up listener).
- **KEYFRAME Y IS ABSOLUTE** (biggest trap of this session): an animation that
  keys y on a node with an authored offset FORCES it back to the keyed value.
  Offset wrappers (Bubble at -400,-470) must never be keyed — add an inner
  zero-offset node (BubbleAnim) and key THAT. Hop: Root(0,0)-relative node.
- rotation keyframes are radians in timelines (0.14 rad tilt, -0.5 rad bar).
- Eyes blink = scaleY on the Eyes group (0.08 at two frames, cubic ease).
- Draw-order corrections after render checks: features must be declared
  BEFORE the face ellipse (first=front), text BEFORE its bubble ellipse,
  teeth before the clap bar, hands before the board.
- Build hygiene: hex ids (0:8e) are INVALID — numeric client:object only;
  VM/asset ids need their own non-colliding range.
- Verification loop: --verify → --screenshot --advance per beat (6/13/21/30)
  → --data-dump confirms bool → release-off-target returns to idle ✓.

## 13. Runner mascot project (2026-09-17, rive 1.0.3) — character animation + re-skins

Project: side-view run cycle, later re-skinned twice (pictogram → cartoon kid →
fitness mascot) with animation contractually frozen. All findings verified live.

### `--advance=N` renders frame N-1
- 30-frame loop: `--advance=1` vs `--advance=31` → pixel-identical (numpy
  max-diff 0). `--advance=30` ≠ `--advance=0` frame: it rendered the frame-29
  pose (5,720 px differing) — initially read as a broken loop wrap.
- So: advance=0 = authored rest pose (no SM step), advance=1 = frame 0,
  advance=N = frame N-1. Loop-wrap proof = advance=1 vs advance=duration+1.
- Rest-pose note: authored static attrs that differ from the f0 keys (e.g.
  opacity keyed 0→1 but authored 1) make advance=0 renders LIE about frame 0.

### One shared CubicEaseInterpolator for the whole file
```xml
<CubicEaseInterpolator x1="0.37" y1="0" x2="0.63" y2="1" id="0:90"/>
<!-- ...132 KeyFrameDoubles: interpolationType="cubic" interpolatorId="0:90" -->
```
- Artboard-level declaration + id reference from many keyframes: verify clean,
  eased motion rendered. No per-keyframe children needed (skill previously
  implied a child; sample rml_triangle shows neither).
- `name="..."` on it = build error "CubicEaseInterpolator has no property
  name" even though `rive schema CubicEaseInterpolator --all` lists `name`
  via Component inheritance (doc drift, rive 1.0.3).

### Re-skin with frozen animation — the keyed-id contract
- Keys target ids; artwork under an id is replaceable. Re-geometried keyed
  SHAPES freely (hair: triangles → rounded-rect locks; shoes: rect →
  upper+sole+toe-cap group) while ids 0:101-103 / 0:27 / 0:57 survived —
  their rotation keys (hair sway, ankle flex) drove the new artwork.
- Nested `Shape` inside a keyed `Shape`: child shapes paint in FRONT of the
  parent's own path and inherit its keyed transform (toe cap + sole inside
  the shoe shape followed the ankle-flex keys). Multi-color sub-assemblies =
  one child Shape per color (a Shape's Fill applies to its own paths).
- Author static rotation/position attrs EQUAL to the f0 key values so the
  rest pose and frame 0 agree.
- Far-limb anti-float rule: compute the limb's max excursion at the keyed
  swing extremes; keep every piece inside the occluder (torso) silhouette
  except a segment that CROSSES its edge — a strip crossing the boundary
  reads attached, a lone cap beyond it reads floating. Iterating: sleeve tip
  4px past the shirt edge was flagged "detached" until shortened inside.

### Gradients, transparency, misc
- LinearGradient/RadialGradient startX/Y endX/Y are PATH-LOCAL pixel coords
  (not normalized). Author predictable space: full-bleed rect with origin
  0/0 at (0,0), gradient 0,0→0,600 for vertical. Verify by PIL pixel probes
  — probe values matched blended key colors exactly (e.g. 0.8·(74,83,104) +
  0.2·(33,38,52) = (66,74,93)).
- Radial: center=start, radius point=end (endX=220,endY=0 → r=220 fade).
- Removing the Artboard's `Fill` makes the .riv background transparent, but
  the CLI screenshot composites an opaque dark backdrop (corner RGBA
  (29,29,29,255)) — alpha cannot be verified from the screenshot alone.
- Enum attrs accept symbolic names (`interpolationType="cubic"`,
  `loopValue="loop"`); official samples use numerics ("1") — both work.
- `rive` rewrites scene.rml after content-changing builds (id stamping on
  id-less elements), not just the "first build" as docs say — agent Edit
  tools then fail with modified-since-read; re-Read before patching. Patching
  via python string-replace sidesteps it but loses tool-level freshness
  tracking; prefer re-Read + Edit.
- Vision-model review of small low-contrast details false-negatives: "speed
  lines absent" — pixel probes proved them rendering at exact keyed opacity.
  Trust probes over eyeballs for subtle elements.

## 2026-09-22 · Flutter runtime pairing with CLI 1.1.0 (rive-flutter 0.14.11 / rive_native 0.1.11)

Context: shipping CLI-built .riv polish animations into a Flutter macOS app.

- `flutter pub add rive` → 0.14.11. `RiveAnimation.asset` (the API in most
  docs/training) does NOT exist in 0.14: undefined_identifier. 0.14 is
  rive_native-based: `FileLoader.fromAsset(asset, riveFactory: ...)` →
  `RiveWidgetBuilder(fileLoader:, builder:)` → switch on `RiveState`;
  `RiveLoaded()` → `RiveWidget(controller: state.controller)` (defaults
  fit contain / center; default artboard + default state machine auto-fire).
- `riveFactory` is REQUIRED. `Factory.flutter` still resolves native symbols
  (dlsym makeFlutterFactory) — there is no pure-Dart path in 0.14.
- Downgrade probe: 0.13.20 (pure Dart, has RiveAnimation.asset) FAILS to load
  CLI 1.1.0-built .riv (file loads error in test). CLI 1.x output requires
  the 0.14/rive_native runtime.
- `flutter test` on host VM: "Failed to lookup symbol 'makeFlutterFactory':
  dlsym(RTLD_DEFAULT)". Fix: `dart run rive_native:setup --verbose --clean
  -p macos` → copies librive_native.dylib to
  <project>/build/rive_native/native/build/macosx/bin/debug_shared/ — one of
  the rootPaths DynamicLibraryHelper.open() probes when
  rive.Platform.instance.isTesting. CI must run this before flutter test
  (build/ is gitignored, so it doesn't ride along).
- Widget-test pattern for autoplay loops (never settle): pump in a loop until
  `find.byType(RiveWidget)` appears — it is only built on RiveLoaded; a
  RiveFailed otherwise silently renders SizedBox.shrink.
- macOS app build: `flutter build macos --debug` pulls the rive_native pod
  via pod install with no Podfile edits. Looping spinner/hero files of
  0.6–2.4 KB each.

## 2026-09-22 · keyed TrimPath silently inert (rive 1.1.0)
- Artboard: open 2-vertex PointsPath + Stroke + <TrimPath end="0"/>; succeed timeline keyed propertyKey 115 (end) 0→1. Build + inspect clean; pixel-dumps showed strokes never drawn (group scale keys DID apply — object invisible purely from trim staying 0).
- Schema says start/end A+B (animatable+bindable) — contradicted live.
- Fix used: wrap each segment in a Node at its start point, rotate to the segment angle, key the node's scaleX 0→1 (ease-out) = draw-on wipe. Verified via redirected-Entry screenshots.
- Same session: 8-bit RGBA PNG pixel-dump beats vision models for verifying tiny art; write a proper PNG filter decoder (3/4 included) before trusting 'it rendered'.

## 2026-09-24 — CLI 1.1.1 announcement and live checks

Source: https://community.rive.app/c/announcements/rive-cli-1-1-1 (plus the
Rive Editor 0.8.5940 announcement on the same page).

- Installed `rive --version` returned 1.1.1. `rive pull --help` confirms that
  pull overwrites linked scene/scripts/shaders/assets, has no merge, and needs
  confirmation (`--yes` for CI); locally added files are not deleted.
- Live `rive <temp-project> --verify --format=json` with malformed line 1 RML
  returned `data.problems[0].line=1,column=1`, matching stderr. JSON positions
  changed from zero-based in 1.0.3 to one-based in 1.1.1.
- Live reverse-order module check: copied the bundled `rml_vm_input` sample,
  added `require('mathutil')` to the importer and declared the module's
  `ScriptAsset` after it. Headless screenshot exited 0 and logged
  `module speed: 0.5`, confirming the dependency-order export fix.
- The announcement also describes `KeyedObject` merging on export, preserved
  script input types on push, stricter audio build checks, four new inspect/LSP
  problem kinds, and drawable custom properties. These are release facts rather
  than locally exercised rules; consult `rive docs`/`rive schema` when needed.
- `rive docs luau/protocols` still says modules must appear before importers.
  That bundled page is stale in 1.1.1; the live check above takes precedence.

## 2026-09-24 — Multi-artboard Editor placement

The la_cabine file's 13 root Artboards omitted x/y, so they overlapped on the
Editor stage after push. Live CLI 1.1.1 check: copied the local RML project into
two temporary dirs, set `x="500" y="300"` on the LoaderLight root Artboard in
one copy, and captured LoaderLight at `--advance=1` from each. PNG SHA-256
hashes matched exactly. Root artboard stage placement can be changed without
shifting that artboard's rendered contents. This does not apply to child nodes.

## 2026-09-25 · keyed knee curves silently dropped on first-built leg chain (rive 1.1.1, UNRESOLVED trigger)

Run-cycle project (p1.1/1 benchmark). Two structurally identical leg chains
(Near Leg→Knee→Ankle, Far Leg→Knee→Ankle), each knee keyed with a 17-key
rotation curve. The first-built chain's knee rendered as if unkeyed (constants
applied, curves did not); the second-built chain animated correctly. Verified
by visual crops (not color masks — see below) and by spiking single keyframes
(changed neighbor frames but not the key's own frame).

Exonerated: node ids (fresh ids 0:50/0:60 failed too), node names (unique names
failed), block order in the animation, artboard child order, interpolation type
(linear vs cubic), rest rotation values, keyframe layout density (9-key vs
17-key), the sibling ankle block, the far-knee block (deleting it didn't fix),
wrapper nodes, flat shin-node restructure.

Fix that worked: rebuild so the fully-keyed leg is constructed SECOND (the
front leg), and give the first-built (back) leg a constant knee bend (0.85 rad)
carried by rest rotation. Visual result fully correct; both legs read properly
articulated.

MEASUREMENT TRAP (cost hours): tracking "shoe position" by exact RGB masks —
antialiased waistband↔shorts boundary pixels pass straight through a ±8 window
around the shoe color (e.g. 181,212,234), producing a phantom constant
~y658 "shoe bottom" that looks like a dead joint. Require ≥3 matching pixels
per row and stay away from garment boundaries.

Not promoted to SKILL.md: trigger not understood; may interact with the
wire-format parentId drift noted in SKILL.md. If reproduced, bisect with
per-frame pixel diffs against a knee-blocks-deleted build, not color masks.

## 2026-09-26 · CLI 1.2.0 re-verification (brew cask, macOS arm64)

User updated to 1.2.0 (announcement: community.rive.app/c/announcements/rive-cli-1-2-0).
Found `rive --version` still 1.1.1: brew metadata knew 1.2.0 but the upgrade hadn't
landed (`brew upgrade --cask rive-cli` completed it — Homebrew installs are pinned;
`rive update`/`rive switch` only work for curl-installer builds under ~/.rive).

Live verification on 1.2.0 (scratch project /tmp/rive12_check + pointer_reactive sample):
- Core loop intact: create → `--verify --format=json` (same envelope, success=true,
  problems[]), `--screenshot --advance=1` exit 0, `--pointer=click@200,200
  --advance=20` exit 0. Exit ladder: `--bogus`=2, `--format=json` w/o mode=2,
  `--verify --once`=2. Watermarking without push.fileId unchanged.
- **ACCIDENTAL LIVE PUBLISH**: ran `rive . --publish=web` expecting an auth-gated
  no-op — user was logged in, so it published instantly (exit 0, no confirmation,
  page live at rive12-check-cfuj8e.rive.to within ~1s; also wrote local signed
  build/rive12_check.riv). Cleanup: `rive . --unpublish=web --yes` → `deleted
  rive12-check`, exit 0; `--list-published` then showed `web not published`.
  ⇒ the publish=web no-confirm trap in SKILL.md is real, verified firsthand.
- `--publish --quiet` prints `./build/<name>.riv` on stdout (captured with
  2>/dev/null); the path also appears in the log stream.
- `--fullscreen`: advertised in the 1.2.0 release notes but ABSENT from the shipped
  cask binary — `unknown flag "--fullscreen"` exit 2, both bare and with
  --screenshot. Release notes > binary in this case; binary wins.
- `rive create` scaffold now declares StateMachine (id 0:7) before LinearAnimation
  (0:6) — matches release notes (Editor opens Animate mode on first-listed).
- rive.yaml gains `window:` (icon label/color/artboard/false — every desktop;
  titleBar integrated + controls + dragHeight — macOS only) and `cursor:` (native
  cursors via bound VM property); headless runs ignore window:. Detail lives in
  `rive docs project/rive-yaml` (integrated_titlebar sample is the worked example).

From release notes, NOT live-verified: push patches objects in place keeping ids
(editors keep keyframes); pushed images carry real width/height; expired-session
message now leads with "Not logged in. Run: rive login"; web runtime accepts
scripts not declared in markup; RML grid layouts / layout participants for
shapes+text+images / Solos in layouts; Windows viewer keyboard+gamepad; SM inputs
marked deprecated in docs in favor of VM properties.

Edits made: SKILL.md verified-line → 1.2.0 + publish=web trap line; CLI_REFERENCE.md
§6.1 --publish[=local|web] row, §6.6 d|data, new §16 (1.2.0 changes); CHANGELOG line.


## 2026-09-28 · pack_fx effects (who_made_this_movie) · rive 1.2.0 + rive-flutter 0.14.5 / rive_native 0.1.5

Moved from SKILL.md (budget): reverse-engineering wire format — ToC = 2-bit wire
types packed in uint32 WORDS; bool=1 byte; uint/enum/Id=varuint;
String/Bytes/List<Id>=varuint length + payload; color=uint32 AARRGGBB;
float=float32. parentId indexes drift vs object order — pair paints↔shapes and
colors↔paints by STREAM ORDER. Parser pattern: `rive_parse.py` / `gen_svg.py`
(LEB128 + property-key objects; defs from `rive schema <Type> --all --json`).
Browser render: @rive-app/canvas, serve the wasm locally, patch the unpkg URL →
`./rive.wasm`.

Verified live this session (iOS 26.5 simulator, debug):
- `--data` cannot set a ViewModelPropertyTrigger: `--data fire: no property at
  this path` (it IS listed by `--data-dump`, type trigger, no value). Workaround
  for screenshots: CLI-only bool `preview` + an extra transition
  (`preview == true` [AND rarity == N]) into the same animation state.
- Default instance without `<ViewModelInstanceTrigger viewModelPropertyId=…/>`:
  `controller.dataBind(DataBind.auto())` then `vmi.trigger('fire')` → null
  (color/number resolved fine). Adding the instance value fixed it; firing then
  drives `fire`-conditioned transitions (proved with
  `stateMachine.onStateChanged((name) => …)` — state names = animation names).
- AND conditions: two `TransitionViewModelCondition` children on one
  StateTransition (trigger + number equal) work at runtime.
- Feather (stroke) glow: sharp/unblurred with `riveFactory: Factory.flutter`,
  soft with `Factory.rive`. CLI screenshots always show it soft.
- Screenshots of short one-shot effects (<1.5 s) via the simulator tool miss
  them (latency); use onStateChanged logs as proof instead.
- `RiveWidget(fit: Fit.contain)` trips `avoid_redundant_argument_values` (it is
  the default).

## 2026-09-29 — judging transparent FX artboards (rive 1.2.0)

- `--screenshot` of a transparent artboard (no Artboard Fill) renders over a
  fixed #1D1D1D; `rive.yaml` `artboard: {background: …}` does NOT change it for
  RML projects (only script-only projects). To judge glows on the real app
  background, render a temp copy with a full-size backdrop `Shape` declared
  LAST in each artboard (draw order reversed → paints behind everything).
- Backup copies named `*.rml` in the project dir compile into the same
  document → "duplicate id" errors. Rename backups (`.src`).
- `blendModeValue` (srcOver/screen/additive/colorDodge) on Shape builds and
  renders in CLI captures; over a near-black backdrop screen ≈ srcOver (mean
  luminance 315.4 vs 315.6) — intensity/shape changes matter far more.
- Trigger-driven one-shots guarded by `preview` only for some enum values
  silently leave other values un-screenshot-able; wire preview for every value.

## 2026-09-30 · Runner character rig (GLM benchmark) — sibling z-order hides detail strokes; rotation convention calibrated (rive 1.2.0)

- **Draw order applies between SIBLING Shapes, killing "detail strokes":** an
  ear-curl Stroke inside a head group was declared AFTER its sibling ear-fill
  Shape → the fill painted IN FRONT and completely hid the curl; two critic
  rounds reported "the claimed curl does not render" while verify/inspect were
  clean. Fix = declare the stroke BEFORE the fill it sits on (or nest it as a
  child Shape of the fill's Shape). Symptom pattern: "added detail invisible,
  build clean" → check sibling order first.
- **Rotation convention, calibrated live via a minimal no-SM test artboard:**
  for a child authored pointing down (+y), tip direction = (sin(−θ), cos θ):
  negative rotation swings the limb toward +x (forward when the character faces
  +x); child rotations compose additively (knee abs = hip + knee rel).
  CALIBRATION TRAP: you cannot calibrate by editing static attrs in a project
  whose state machine plays an animation — frame-0 keys override static attrs
  at --advance=1. Build a bare Artboard+Nodes scene with no SM instead.
- Verified headless review loop for character animation: render 8 frames
  (--advance=f+1), contact sheet + GIF via PIL, dispatch a vision critic agent
  with target + frames + GIF; loop-wrap proof = --advance=1 vs --advance=31
  pixel-diff (max 1 = antialiasing noise).

## 2026-10-02 · CLI 1.3.0 verification pass (rive 1.3.0)

- Binary flipped 1.2.0 → 1.3.0 mid-session at /opt/homebrew/bin/rive
  (Homebrew cask). `rive uninstall` still refuses there: version management
  remains installer-only under ~/.rive.
- ✅ Text API live: `cp -R "$(rive samples --path)/scripted_text"` → `--verify`
  clean, `--screenshot --advance=1` renders. Script uses
  `context:font('IBMPlexSansArabic-Regular')` (nil check → `return false`),
  `Text.new()`, `:append(msg, {font=, size=, paint=})`, `sizing='autoHeight'`,
  `maxWidth=520`; Arabic RTL shaped by the runtime, not the script.
  New samples present: scroll_demo, scripted_text, text_island(_as),
  text_string(_as), text_rain(_as), cursor_demo, mesh_skin_as, particles_as,
  wavy_effect_as.
- ✅ Entry-only SM layer verifies green: scaffolded a project, deleted
  `AnyState` + `ExitState` from the layer → `rive . --verify` exit 0
  (0 errors, 0 warnings). Write-back NOT observed under `--verify` or `--once`
  (announcement says ids are "written back into your markup so they stay the
  same across pushes" — likely a push-time behavior; untested, not logged in).
- Docs-coverage audit (constraint: skill records only what official docs
  lack, or where they drift): `rive docs luau/api/text` covers the script text
  API; `format` (line ~534) + `gotchas` (~105) cover Any/Exit auto-add;
  `rive docs push` covers `rive ls` flags; `luau/api/gpu` covers gpuTarget.
  NOT in docs: `ListenerViewModelChange` `inputValue`/`inputValueIndex`,
  `wheelInteractive`, the "targets a Node that is not exported" build error.
- `print("a", 1)` tab claim NOT verified — test script wasn't attached via
  ScriptedLayout/ScriptAsset, so `advance` never ran and no console line
  appeared. Retry properly before trusting it.
- 1.3.0 scaffold `scene.rml`: same shape as 1.2 (SM before timeline,
  Any/Exit/Entry emitted, defaultStateMachineId set). Generated `AGENTS.md`
  still a lean workflow doc (schema/docs lookups, verify/inspect/screenshot
  gates, previewer rules) — no coverage of new commands/APIs; the skill's
  division of labor (AGENTS.md basics ↔ skill traps) is unchanged.

## 2026-10-08 · CLI 1.4.0 verification pass (rive 1.4.0)

- Trigger: user's rive_template/ scaffolded with 1.4.0 (brew cask at
  /opt/homebrew/Caskroom/rive-cli/1.4.0). Community announcement page
  (Circle, JS-only) unreadable by fetch; user pasted the release notes;
  everything below was still re-derived live from binary + `rive docs`.
- ✅ Unchanged: verify JSON envelope, screenshot+advance, exit ladder
  (bogus=2, json-no-mode=2, two-modes=2), pointer click sequencing,
  scaffold shape (SM before timelines, Any/Exit/Entry, defaultStateMachineId;
  AGENTS.md lean + new "don't preview via push / no web-runtime preview"
  lines; .gitignore = build/ only).
- ✅ Keying by name: scaffold + `<Node id="0:20">` + `<KeyedObject
  objectId="0:20"><KeyedProperty property="x">` + two KeyFrameDouble keys →
  verify green. `property="xx"` → exit 1 `Node has no property "xx" to
  animate; did you mean "x"?`. `propertyKey="13"` (x) still green. `rive
  docs format` §Animation documents the whole rule (name resolved on the
  KeyedObject's type; name or number, or both if they agree).
- ✅ `--touch=tap@250,250` and `--pointer=wheel@250,250:0,-120` captures
  exit 0; unconsumed wheel logs `wheel: nothing at 250,250 scrolled. No
  scroll view under it can move that way, or its wheelInteractive is off`.
- ✅ fetch: generator script attached via ScriptedLayout + explicit
  ScriptAsset. Without `--allow-net`: rejects, print shows `FETCH_FAIL
  disabled: network access is not enabled for scripts in this host`.
  With `--allow-net --advance=300`: `FETCH_OK status=200`
  (https://example.com/). API per `rive docs luau/api/net`.
- ✎ THE TRAP (~30 min): generator WITHOUT the `: Layout<T>` return
  annotation → verify GREEN, build GREEN, screenshot writes, script NEVER
  runs. Only diagnostic: raw untimestamped `ScriptAsset doesn't have a
  generator function <name>` ×2 at load (grep for "generator function").
  Isolation: text_rain sample runs clean; strip ONLY the annotation from
  its return line → error returns. `rive inspect` shows
  generatorFunctionRef: 0 for working samples too — inspect is NOT the
  tell. Hit along the way: (a) `function T:m(self: T)` double-declares
  self → lint error; use `function T.m(self: T)` or assemble locals into
  the literal (sample idiom). (b) `async(fn)` rejects void callbacks
  (`Expected this to be 'T', but got '()'`) → use `andThen(ok, err)`.
  (c) once annotated, protocol contract is type-enforced: state needs a
  named `type` + exact literal (ad-hoc `done` flag must be in the type);
  `advance` returns boolean.
- ✅ `rive build` exists (`rive build --help`): ships app + installs on
  device; --device/--android/--ios/--aot/--backend/--id/--title.
- 📄 release-notes-only (recorded CLI_REFERENCE §18): libraries /
  .libraries + override:, --android preview, VS Code View Models panel +
  Break on Value Change, --bench times publish build, Stroke position,
  pointerScroll, vector z=0, WGSL aliases, viewer fixes (nested-SM
  triggers, transition-sees-listener-write, COLRv1, virtualized grids).

## Flutter runtime pairing — relocated here from SKILL.md 2026-10-08 (verified vs rive CLI 1.1.0 / rive-flutter 0.14.5)

- rive-flutter **0.14.x has NO `RiveAnimation`** (the pre-2025-docs API). Use
  `FileLoader.fromAsset(asset, riveFactory: Factory.flutter)` →
  `RiveWidgetBuilder` → `RiveLoaded` → `RiveWidget(controller:)`. Even
  `Factory.flutter` calls the native lib via FFI; `riveFactory` is required.
- **0.13.x can't load CLI 1.x .riv** (need 0.14). `flutter test` dlsym-fails
  until `dart run rive_native:setup -p macos` (CI needs it).
- (0.14.5) A VM **trigger needs `<ViewModelInstanceTrigger>` in the default
  instance** — else Flutter `vmi.trigger('x')` is null; CLI builds/dumps clean.
- `Feather` glows render only with `Factory.rive`; `Factory.flutter` draws hard.

## 2026-10-08 · Review implementation pass (external skill review, rive 1.4.0)

- Source: external review of the four skill files. Implemented: mode-table
  correction, Quality & Completion Gate in SKILL.md, mandatory runtime-log
  check, version marks, XML patterns relocated here (below), NOTES historical
  notice + archived-proposal marker, description trigger scoping
  ('animated character' → 'rive character'), safety guard for remote/
  destructive ops, milestone-based core loop (verify every edit, screenshot
  at pass milestones).
- OPEN TEST (pending, needs a toggle scene): does the 1.4.0 "transition sees
  listener-written value same-frame" fix also remove the need for an
  --advance separator between two CLICK listeners? Until tested, SKILL.md
  keeps the separator with a 1.4.0 caveat. Test recipe: VM-bool toggle scene
  (pattern below), `--data-dump=-` with two clicks back-to-back vs separated.
- ✅ Screenshot dir auto-create (1.4.0): fresh scaffold (no build/) +
  `rive . --screenshot=build/rest.png` → succeeds, dir created. §12 item 2
  version-marked. (Deep custom paths untested.)

## Schematic RML patterns (moved from SKILL.md 2026-10-08 — PLACEHOLDER IDS)

> Both blocks are SCHEMATIC: `0:55`, `0:98`, `VM-prop`, `<target>` are
> placeholders. Mint fresh `client:object` ids per project (numeric only,
> unique across ALL .rml files) and resolve `propertyKey="634"` (boolean) via
> `rive schema` for the actual type.

**VM-bool toggle (click flips)** — listener reads via negate converter, writes back:
```xml
<StateMachineListenerSingle targetId="<target>" listenerTypeValue="click">
  <ListenerViewModelChange fromViewModelProperty="true" fromDataBindId="0:55">
    <BindablePropertyBoolean>
      <DataBindContext sourcePathIds="VM-prop" propertyKey="634" id="0:55" converterId="0:98"/>
      <DataBindContext sourcePathIds="VM-prop" propertyKey="634" direction="true"/>
    </BindablePropertyBoolean>
  </ListenerViewModelChange>
</StateMachineListenerSingle>
<!-- root: <DataConverterBooleanNegate name="Not" id="0:98"/> -->
```

**Condition-guarded transitions need BOTH comparators** (missing the value
comparator = condition never fires, verify stays green):
```xml
<StateTransition stateToId="…" duration="12">  <!-- ms! -->
  <TransitionViewModelCondition>
    <TransitionPropertyViewModelComparator>
      <BindablePropertyBoolean>
        <DataBindContext sourcePathIds="VM-prop" propertyKey="634"/>
      </BindablePropertyBoolean>
    </TransitionPropertyViewModelComparator>
    <TransitionValueBooleanComparator value="true"/>  <!-- REQUIRED -->
  </TransitionViewModelCondition>
</StateTransition>
```

## 2026-10-08 · Second review pass (external, rive 1.4.0)

- Implemented: capture-flag modifier fix (--pointer/--touch/--key/--gamepad/
  --advance REQUIRE a capture mode; --data/--viewport/--fit are config
  modifiers — --viewport also sizes the live preview window); gate now
  requires POSITIVE script-execution proof (observable effect: print marker /
  changed frame / data-dump value — logs.file is append-only, so "no errors"
  can be stale and is never evidence of running); loop test qualified
  (pixel-identity only for deterministic fixed-duration loops; procedural /
  time-driven = continuity check); §15.3/§15.4/§12.9 refs normalized to
  "§15 item N" form (Section 15 has no .3/.4 subsections); generator-
  annotation rule marked live-verified on Layout only — other six protocols
  expected-untested.
- Benchmark idea from review (user action, kept here so it isn't lost): run
  the same Rive agent task twice — with and without the skill — and compare
  successful builds, debugging iterations, runtime failures, visual defects,
  final animation quality. Tells which sections earn their lines.


## 2026-10-09 · Rigging a single raster illustration (dog: sit/bark/paw) (rive 1.4.0)

Verified live end-to-end (screenshots + pointer clicks + --data-dump):
- **Raster cut-out rig works well with plain `Image` + node chains.** Cut the PNG
  into parts with PIL/OpenCV (polygon masks), export cropped PNGs + offsets,
  place each with `<Image x=cropX y=cropY originX="0" originY="0">` inside
  `Pivot(px,py) > keyed node(s) > Space(-px,-py)` — every part stays authored
  in source-image pixels, one outer `Dog` node scales the lot.
- **Seamless rest pose:** the part gets a feathered mask from its cut line; the
  body keeps the original pixels for ~24px PAST the cut (erase starts below),
  so the part overlaps identical pixels at rest (max diff vs original ≈ 0).
- **Put limbs BEHIND the body** (later sibling): translating a leg up hides its
  top under the torso — a "folded" hind leg for a sit pose is just leg
  rotation = −bodyRotation + translate up so only the paw peeks out.
- **Straight cut edges read as fake once parts move.** Shape every exposed cut
  as the art's fur tufts: per-column triangular "spike" offsets applied with
  `cv2.remap` (shift mask columns down by prof[x]) — haunch/head seams vanish.
- Behind the head, keep the body opaque (erase only ears/top) and inpaint the
  face features (`cv2.inpaint` + blur) so head motion never shows a 2nd face.
- Jaw for barking: cut lower lip+tongue as its own part, paint the head layer's
  jaw region dark mouth colour; key jaw y+scaleY → open mouth.
- Translating nodes inside a rotated parent: convert world offsets with R(−θ)
  in the generator (`x = wx cosθ + wy sinθ`, `y = −wx sinθ + wy cosθ`).
- Pose blend: two one-key pose timelines + `StateTransition duration=600`
  with a nested `CubicEaseInterpolator` = smooth eased sit/stand both ways.
  Keep text label swaps on their OWN layer with duration-0 transitions, or
  the posture blend cross-fades "Sit"/"Stand" into overlapping text.
- VM trigger from a button: `ListenerViewModelChange > BindablePropertyTrigger
  propertyValue="1" > DataBindContext propertyKey=686 direction=true`; reading
  side `TransitionValueTriggerComparator` (pattern from keyboard_menu sample).
- `--viewport` larger than a fixed-size artboard renders it at 1x in the
  top-left — it does not zoom. To inspect detail, crop+upscale with PIL.
- Generator script (Python → RML) with an id counter beat hand-editing for a
  ~420-object file; tools kept beside the project, not inside it.
- (polish pass, same day) **Image meshes WITHOUT bones work and are keyable:**
  `<Image originX="0" originY="0"><Mesh triangleIndexBytes=…>` with grid
  `ContourMeshVertex`/`MeshVertex` (no Skin) renders; vertex x/y are image-local
  PIXELS from the top-left when origin is 0,0 (verified vs a plain Image), and
  keying `MeshVertex` x/y in a LinearAnimation deforms the bitmap. Generator
  pattern: deform fn(X,Y)->(X',Y') evaluated per keyframe, key only vertices
  that move. Used for: mouth open with pinned corners (dy = A·sin(πu)), bendy
  tail (rotation weighted by distance from base), wrist flex, ear twitch.
  Two layers keying the same vertices: later layer wins only while its state
  has keys (an empty "rest" anim leaves the earlier layer in control).
- Secondary motion on top of a pose BLEND: separate "FX" layer with one-shot
  settle/push timelines keyed on extra chain nodes (Body.FX/Head.FX/Tail.FX) —
  hierarchy makes them additive to the blended pose.
- `cursor: {property: cursor}` in rive.yaml + enter/exit listeners writing a VM
  string "pointer"/"arrow" — `--data-dump` shows cursor=pointer on hover.
- (sit rework, same day) **Articulated torso from ONE bitmap = two-frame linear-blend
  skinning baked into keyed mesh vertices** (no Rive bones): front frame = Body
  node transform, rear frame = extra matrix; vertex = lerp(v, Rear·v, w(x,y)) with
  a wide smoothstep seam (narrow seams fold triangles → visible straight creases).
  Attachments (head/tail/legs) get node transforms SOLVED from desired world
  placement: L = T(-pivot)·Parent⁻¹·World·T(pivot), decomposed to x/y/rotation.
  Authored transitions = pose(p) sampled every 2 frames (linear keys) along
  Catmull-Rom curves for p/head-lag/tail-lag/squash — arcs stay correct where a
  state blend would lerp vertices along chords. Pitfall: p<0 "anticipation"
  lifts the rear off world-pinned legs → gap; animate anticipation on other
  channels instead. Draw-order swap trick: a front-layer copy of a part riding
  the same solved transform, opacity faded in while both overlap.
