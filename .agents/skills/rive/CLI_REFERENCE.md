# Rive CLI — Complete Reference & Test Guide for AI Agents

> Source: https://rive.app/docs/cli/agents (plus overview, getting-started, examples, commands reference, project-config).
> Full docs index: https://rive.app/docs/llms.txt
> Purpose: give an AI agent (Claude Code, Cursor, ZCode, etc.) everything needed to install, drive, and **test** the Rive CLI without re-reading the docs.
>
> **Baseline validated live against rive 1.0.3 on 2026-09-16. CLI 1.1.1 updates verified 2026-09-24; CLI 1.2.0 re-verified live 2026-09-26 — see §16; CLI 1.3.0 checked 2026-10-02 — see §17; CLI 1.4.0 checked 2026-10-08 — see §18. §15 retains the original test record.**

---

## 1. What the Rive CLI is

A command-line tool to **create, preview, inspect, and publish Rive graphics** without opening the Rive Editor.

- Author scenes in **RML** (Rive Markup Language), **Luau** scripts (`.luau`), and **WGSL** shaders (`.wgsl`) as plain text files.
- Builds `.riv` files (for apps/games/runtimes) and `.rev` files (openable in the Rive Editor).
- Live preview window rebuilds and reloads on every file save.
- Designed to pair with coding agents: `rive create` generates an `AGENTS.md` that teaches the agent the workflow (type lookups + self-verification).
- Headless rendering/testing: screenshots, simulated input, view-model data, Luau unit tests — no window, no login. CI-friendly.
- Projects are folders of text + assets → normal git diff/review.

RML docs: https://rive.app/docs/runtimes/advanced-topic/rml

---

## 2. Installation

**Platforms:** macOS (Apple Silicon), Linux x86_64, Windows.
**Account:** NOT required for local create / preview / build / test. Works signed out and offline.

### macOS / Linux installer
```bash
curl -fsSL https://releases.rive.app/cli/install.sh | sh
echo 'export PATH="$HOME/.rive/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Windows (PowerShell)
```powershell
irm https://releases.rive.app/cli/install.ps1 | iex
```

### Homebrew
```bash
brew install --cask rive-app/tap/rive-cli
```
⚠️ Homebrew caveat: `rive update`, `rive switch`, `rive uninstall` only work on installer builds (under `~/.rive`). With Homebrew use `brew upgrade` / `brew uninstall --cask rive-cli`.

### Verify install
```bash
rive doctor        # checks version, auth, ports, project
rive --version
rive --help
```

Install/state root: `~/.rive` (override with `RIVE_HOME`).

---

## 3. Authentication

```bash
rive login       # sign in with Rive account
rive logout
rive whoami      # shows signed-in identity (exit 3 if signed out, 7 if service unreachable)
```

| Needs login? | Commands |
|---|---|
| ✅ Yes | `--publish`, `--rev`, `rive push`, `rive pull`, `rive create --from-remote-file`, `rive ls` / `rive workspace` / `rive open` (1.3.0). Gated modes check the session live |
| ❌ No (offline ok) | preview window, `--once`, `--verify`, `--test`, `--screenshot`, `--serve`, `--headless-serve` |
| ❌ No session | `create`, `docs`, `samples`, `schema`, `inspect` |

Credentials stored at `~/.config/rive/app.rive.cli/` (macOS/Linux, honors `XDG_CONFIG_HOME`); Windows Credential Manager.

**Signing rules:** files containing scripts destined for the **web** MUST be built with `--publish` — unsigned scripts are rejected by the CDN and web runtimes. Files without scripts are unaffected.

**Watermarking:** `--publish` can watermark an unbound project. `rive push` binds a project to a Rive file (`push.fileId` in `rive.yaml`). Use `--once` for unsigned local builds.

---

## 4. Top-level commands

| Command | Purpose |
|---|---|
| `rive create [dir]` | Scaffold project: `rive.yaml`, `scene.rml`, `AGENTS.md`, `CLAUDE.md`, `.gitignore` |
| `rive <project-dir>` | Open preview window, rebuild on save (defaults to `.`) |
| `rive login` / `rive logout` | Auth |
| `rive whoami` | Identity |
| `rive docs [topic]` | Authoring docs (built in) |
| `rive samples` | Clone a runnable sample project |
| `rive schema <Type>` | Type/property lookup |
| `rive inspect [dir]` | Print resolved scene as JSON |
| `rive push [dir]` | Build and upload to a linked Rive file |
| `rive pull [dir]` | Overwrite linked local build inputs with the remote file; no merge (`--yes` skips confirmation) |
| `rive ls [projectId [folderId]]` | Browse account projects/folders/files with ids; `--all`, `--recent`, `--plain`, `--json`, `--workspace=<id>` (1.3.0) |
| `rive workspace [<id>]` | Show / switch the current workspace (1.3.0) |
| `rive open <fileId>` | Open a file in the web editor; `--print` = url only (1.3.0) |
| `rive doctor [dir]` | Health check: version, update, auth, live-link, project |
| `rive build [dir]` | Ship the project as an Android/iOS app in the Rive player and install it on a connected device: `--device=<name>`/`--android`/`--ios`, `--aot`, `--backend=<gl\|vulkan>`, `--id=<id>`, `--title=<name>` (1.4.0; flags ✅ from `--help`, run 📄 untested) |
| `rive lsp` | Language server over stdio (editors) |
| `rive update` / `rive switch` / `rive uninstall` | Version management (installer builds only) |
| `rive analytics on\|off` | Usage analytics |

---

## 5. Project anatomy

### 5.1 What `rive create myproject` generates
- `rive.yaml` — config (`name` + build logs; everything else optional)
- `AGENTS.md` — instructions for coding agents (lookup + self-check workflow)
- `.gitignore`
- `scene.rml` — artboard + timeline + state machine that plays it on load

New empty projects render as "a dark rectangle" in preview — expected.

### 5.2 Automatic file discovery (no manifest)
| Extension | Treated as |
|---|---|
| `.rml` | Scene markup — all compile as one document; ids shared across files but must be unique |
| `.luau` | Scripts/modules (always compiled, referenced or not) |
| `.as` | AnimaScript scripts (TypeScript syntax → wasm via the CLI's `rasc`; attach with `<ScriptAsset file="…as" name="…">`; `rive docs animascript/protocols`) |
| `.wgsl` | Shaders (always compiled) |
| `.png` `.jpg` `.jpeg` `.webp` | Images |
| anything else | Blob asset, findable by name |

- **Embedding rule:** assets embed only when referenced (`file=` in RML or script lookup); unused assets add nothing.
- **Auto-skipped:** dot-files/dirs, `rive.yaml`, `output.dir`, `*.riv`, `*.rev`, `*.log`.
- RML asset paths are project-relative (e.g. `<FontAsset file="Montserrat.ttf" .../>`).

### 5.3 `rive.yaml` reference
A project = any directory containing a `rive.yaml`. Only `name` is required.

```yaml
name: myproject        # required; also the import name for other projects
main: main             # default artboard (else first declared)
debugLevel: 0
optimizationLevel: 2

artboard:              # defaults for generated artboards (only when no .rml)
  width: 800
  height: 800
  background: "#FF1D1D1D"   # MUST be quoted — bare # is a YAML comment.
                           # #RRGGBB or #AARRGGBB; invalid → silent fallback to default

artboards:             # per-artboard overrides; keyed by layout script path minus .luau
  main:
    width: 1920
    height: 1080

exclude:               # fully excluded from bundling; exact path / dir / globs (* and ?)
  - docs

excludeFromRev:        # dropped from .rev only (.riv and preview keep everything)
  scripts: ["*_test"]
  artboards: ["tests/*"]
  assets: ["raw_*"]
  contents: ["logo"]   # strips asset bytes, keeps reference unembedded

libraries:             # other project dirs importable via require('lib:shared_widgets/button')
  - ../shared_widgets  # nested deps resolve; shared deps load once; cycles error
  # (1.4.0) downloaded remote libraries are listed here too — see §18

revFlavor: editable    # or "library" (importable by others)

output:
  dir: build           # default: build

logs:
  file: build/rive.log          # append-only: problems + script print + system messages
  problems: build/problems.log  # rewritten each build; one build per file — best for scripting
```

⚠️ Unknown keys are silently ignored; a misspelled `artboards:` entry won't fail the build.
Globs: `*` matches any run of chars including `/`; `?` matches one char.

### 5.4 Creating from an existing editor file
Export a `.rev` from the Rive Editor, then:
```bash
rive create myproject --from-rev=myfile.rev
# omit dir → uses the .rev's own name (myfile.rev → myfile/)
```
Produces `scene.rml` + every script/shader/asset as separate files, matching the Editor's Assets panel layout. Target dir must be empty or new.

---

## 6. `rive <project-dir>` — build modes, modifiers, capture

### 6.1 Build modes (mutually exclusive; `--screenshot` counts as one; none = live preview)
| Flag | Effect | Exit on errors |
|---|---|---|
| `--verify` | Compile-check, write nothing | 1 |
| `--once` | Write unsigned `.riv` to `build/<name>.riv` | 1 |
| `--publish[=local\|web]` | `local` (default): write signed `.riv`; requires login; watermarked until bound. `web`: build, sign, publish a hosted page (1.2.0, §16) | 1 |
| `--test` | Run Luau `Tests` scripts | 6 on test failure |
| `--screenshot[=<path>]` | Headless single-frame PNG (default `build/<name>.png`) | — |

**Authoritative mode set (1.4.0):** ALL of `--verify --once --publish --unpublish --list-published --test --bench --screenshot --semantics --data-dump` are mutually exclusive build modes — one per run (two → exit 2 with `use only one of editor, --verify, --once, --publish, --unpublish, --list-published, --test, --screenshot, --semantics, --data-dump`). `--pointer/--touch/--key/--gamepad/--advance` REQUIRE a headless capture mode (`--screenshot`/`--semantics`/`--data-dump`). `--data`/`--viewport`/`--fit` are CONFIG modifiers: `--viewport` also sizes the live preview window (§6.3) and `--fit` maps the artboard into window and captures alike. Verified live 1.0.3 → 1.4.0.

### 6.2 Modifiers
| Flag | Effect |
|---|---|
| `--init` | Write `rive.yaml` if missing, then continue |
| `--rev=<path>` | Also write editor `.rev`; needs login; combines with `--once`/`--publish`; alone = `--once` build; **refused** with `--verify`/`--test`/`--screenshot` |

### 6.3 Capture & scene driving
| Flag | Effect |
|---|---|
| `--viewport=<WxH>` | Layout size (capture size with screenshot; window size when watching). Default: artboard size |
| `--data=<path=value>` | Set a view-model property before running; repeatable; path segments are property names (`level=100`, `battery/level=100`). Unmatched path → logs `data: no property at "<path>"`, dropped, build still succeeds |
| `--pointer=<kind@x,y>` | Simulate pointer at artboard coords; kinds: `down` `up` `move` `click` (click = move+press+release, frame between each). Repeatable |
| `--pointer='drag@x1,y1>x2,y2[:steps]'` | Drag gesture; steps default 8; total frames = steps + 3. **Quote it** (`>` = shell redirect) |
| `--advance=<N\|Ns\|Nms>` | Step scene forward; repeatable; runs in flag order with interactions. Bare N = whole 60fps frames; `1s`/`250ms` = animation time converted to 1/60s frames (+ one shorter remainder); decimals allowed on time forms (`1.5s` = 90 frames). Rejects sign/whitespace/trailing text/decimal frame counts/>32-bit uint → exit 2. Replaces `--frame` (passing `--frame` errors, naming `--advance`) |
| `--data-dump[=<path>]` | Dump bound view-model values, globals, nested artboards as JSON; default `build/<name>.data.json`; `-` or `stdout` → stdout |
| `--data-dump-filter=<paths>` | Comma-separated property paths, globs allowed (`battery/*,score`) |
| `--data-dump-every=<N\|Ns\|Nms>` | Sample every N frames as JSON Lines; header + frame-0 baseline + changes only |
| `--artboard=<name>` | Launch artboard; unknown name **silently falls back to first** |
| `--bench=<frames>` | Headless frame timing (advance/render stats + WASM memory growth). Own build mode — no combining with other modes or `--advance`/`--pointer`/etc. Renders at artboard size, ignores `--viewport`. 300 warm-up frames precede timed ones |

**Ordering rules:** interactions run in the order written. `--pointer` and `--advance` require `--screenshot`, `--semantics`, or `--data-dump`.

### 6.4 Serving
| Flag | Effect |
|---|---|
| `--serve[=port]` | Push builds to connected players; default port `9640` |
| `--headless-serve` | Serve with no local window |

### 6.5 Other
| Flag | Effect |
|---|---|
| `--quiet` | No terminal log at all, **including compiler errors** — rely on exit code / `--format=json` / `logs.problems` |
| `--optimize` | Luau O2 instead of O1 (faster, harder to debug) |
| `--immediate` | Render on main thread |
| `--format=json\|human` | `human` default; `json` requires a build mode (`--once`/`--verify`/`--publish`/`--test`), prints one JSON report to stdout |

### 6.6 Preview window terminal commands (when watching)
`s`/`screenshot [path]` · `p`/`pause` · `a`/`artboard [name]` · `f`/`fit [mode]` (bare `f` lists modes) · `z`/`size` (resize to artboard, re-follow) · `d`/`data [path]` (write bound data as JSON; `-` = stdout) · `rev [path]` (needs login) · `?`/`help`

---

## 7. Per-command details

### `rive create`
```
rive create                 # prompts for name
rive create <dir>           # `.` = cwd
rive create [dir] --from-rev=<file.rev>
```

### `rive schema`
```
rive schema <Type>
rive schema --search <text>
```
- `--list` — pick a type (prints all type names where no picker can draw)
- `--animatable` — only keyable properties
- `--bindable` — only data-bindable properties
- `--all` — include editor-only properties

### `rive docs`
```
rive docs
rive docs <topic>        # e.g. layout, luau/protocols
rive docs --list
rive docs --search <text>   # matching lines across all topics
rive docs --path         # print docs dir on disk
```

### `rive samples`
```
rive samples             # interactive picker → copies into new dir
rive samples --path      # print samples dir
```
Samples (✅ listed live on 1.3.0): `hello_rive`, `rml_triangle`, `rml_vm_input`, `rml_split`, `pointer_reactive`, `input_demo`, `text_input`, `tests_demo`, `cursor_demo`, `integrated_titlebar`, `keyboard_menu`, `scroll_demo`, `scripted_text`, `text_island`(+`_as`), `text_string`(+`_as`), `text_rain`(+`_as`), `mesh_skin_as`, `particles_as`, `wavy_effect_as`.
Non-interactive copy:
```bash
cp -R "$(rive samples --path)/rml_triangle" myproject
rive myproject
```

### `rive inspect [dir]` (default `.`)
- Prints resolved scene as JSON.
- `--json` (default), `--all` (editor-only props), `--artboard=<name>` (unknown name → empty `artboards`, still exit 0).
- Exit 1 on any error in `problems`; exit 1 + stderr message if no `rive.yaml`.

### `rive doctor [project-dir]`
- Five checks: `version`, `update`, `auth`, `live-link`, `project` — each `ok`/`warn`/`fail`.
- Exit 0 when all ok/warn; 1 on any fail. Missing session = warning only.
- `--format=json` — machine-readable report.

---

## 8. Exit codes

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | Build errors, or any failure without a specific code |
| 2 | Parsed-but-rejected flag values (`--pointer`, `--data`, `--advance`, `--viewport`); `--frame` (removed); bad `--format` value; `--format=json` without build mode; two build modes at once; `--rev` with non-writing mode; interaction without `--screenshot`; bare `rive` outside a project |
| 3 | Not logged in / session rejected |
| 6 | Test failures (build itself fine) |
| 7 | Service unreachable; safe to retry |

⚠️ **Unrecognized flags exit 2** with `unknown flag "--bogus"; rive --help lists them` — live-verified on 1.0.3 and again on 1.4.0 (the old web docs' "silently ignored" claim was already fixed by 1.0.3; see §15 item 4). Bare words are read as project dir; last one wins — *a green exit is not proof your flags landed* (typo'd flag VALUES, e.g. an unknown `--artboard` name, still fall back silently — §12 item 9).

---

## 9. JSON output (`--format=json`)

Requires a build mode. One JSON object on **stdout**; logs stay on **stderr**.

```json
{
  "success": true,
  "command": "build | verify | publish | test",
  "data": {
    "riv": "path or null (--verify and failed builds)",
    "bytes": 1234,
    "buildMs": 42,
    "problems": [
      { "severity": "error|warning|hint", "kind": "...", "code": "...",
        "script": "...", "line": 1, "column": 1, "message": "..." }
    ],
    "passed": 3, "failed": 1, "noTestsFound": false,
    "failures": [ { "test": "...", "line": 0, "message": "..." } ]
  },
  "errors": ["script:line message"],
  "warnings": []
}
```
- `passed`/`failed`/`noTestsFound`/`failures` appear for `test` mode; `riv`/`bytes`/`buildMs` for build modes.
- CLI 1.1.1 JSON `line`/`column` are **one-based**, matching the terminal log and `problems.log`.

---

## 10. Environment variables

| Variable | Effect |
|---|---|
| `RIVE_API_BASE` | API host; custom host gets its own stored login |
| `RIVE_NO_TUI` | Any value except `0` disables pickers |
| `TERM` | unset/empty/`dumb` disables pickers |
| `NO_COLOR` | Colorless pickers |
| `RIVE_HOME` | Install/state root (default `~/.rive`) |
| `XDG_CONFIG_HOME` | Relocates credential dir (macOS/Linux) |
| `RIVE_DOCS_DIR` | Dir `rive docs` reads |
| `RIVE_SAMPLES_DIR` | Dir `rive samples` copies from |
| `RIVE_ANALYTICS` | Forces consent: `on/1/true/yes` or `off/0/false/no` |

Pickers draw on **stderr** — redirecting stdout doesn't suppress them. Where none can draw (`TERM=dumb`, `RIVE_NO_TUI=1`, non-terminal stdin as in CI), the CLI falls back to printing the list.

---

## 11. The AI agent workflow (from the official agents guide)

1. **Create a project** — `rive create myproject`. The generated `AGENTS.md` tells the agent how to look up the CLI reference and check its work. Read it when opening the directory.
2. **Start the preview** — `rive myproject` in its own terminal; leave it running. Rebuilds + reloads on every save.
3. **Open the folder in the agent** — any agent that can read/write files and run shell commands. No further setup.
4. **Describe what you want** — plain language. The agent then:
   - reads `AGENTS.md`
   - looks up types via `rive docs` / `rive schema`
   - writes RML + Luau
   - self-checks with `rive <dir> --verify` and `rive inspect`
   - renders `rive <dir> --screenshot` on request

Official example prompt:
> "Build a weather card: a rounded panel with the city name, a temperature readout, and an icon that animates when it rains. Bind the temperature to a view model property so the host app can set it."

**Guidance:** work in stages, not all at once — wireframe → structure → content → detail. Surfaces layout/sizing problems early and lets the human redirect mid-task.

---

## 12. Gotchas cheat-sheet (read before testing)

1. **No `--advance` = authored rest pose**, not the animation's opening frame. Start previews at `--advance=1`. **`--advance=N` renders frame N−1** (advance=1 = frame 0); loop-wrap proof = `--advance=1` vs `--advance=<duration+1>` rendering pixel-identical (verified rive 1.0.3, 30-frame loop).
2. **Screenshot paths resolve against the CWD**, not the project dir. ≤1.3: missing directories fail with only `screenshot failed: <path>` — create the directory first. 1.4.0: `build/…` targets are auto-created (verified 2026-10-08 on a fresh project with no `build/`); for deep custom paths `mkdir -p` is still the safe habit.
3. **Frame between clicks matters:** a listener's written value isn't visible to the next listener until a frame passes. Back-to-back clicks may both act on the old value → put `--advance` between them. (1.4.0 viewer fix lets *transitions* see listener-written values in the same frame — §18; the listener→listener case is untested on 1.4.0, so keep the separator.)
4. Quote drag pointers: `--pointer='drag@200,300>200,80:12'` (the `>` is shell redirection).
5. `--bench` is its own build mode; renders at artboard size, ignores `--viewport`; won't combine with `--advance`/`--pointer`/etc.
6. `--quiet` silences compiler errors too — use exit codes / JSON / `logs.problems`.
7. In CLI 1.1.1, JSON line/column are one-based, matching the terminal.
8. Unknown flags exit 2; typos are reported.
9. `--artboard` with a wrong name silently falls back to the first artboard.
10. `--data` with an unmatched path is dropped (warning only), build succeeds with the authored value.
11. Background color in `rive.yaml` must be quoted (`"#1D1D1D"`) or YAML treats it as a comment.
12. Publishing on CI needs a signed-in machine (browser login); everything else runs on CI runners.
13. Empty project preview = dark rectangle (expected).

---

## 13. TEST PLAN — scripted checks for an agent

> **Historical record of the live 1.0.3 run (2026-09-16).** Commands below reflect 1.0.3 behavior; where §12/§15–§18 differ, the newer section wins — e.g. Phase 6's `--data-dump --once` was later found invalid (`--data-dump` is its own mode, §15 item 3); Phase 4's `mkdir shots` is only needed for non-`build/` paths on 1.4.0 (§12 item 2).

Run in order; expected result after each. Platform here: macOS (Apple Silicon).

### Phase 0 — Install & health
```bash
curl -fsSL https://releases.rive.app/cli/install.sh | sh
echo 'export PATH="$HOME/.rive/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
rive --version                          # ✅ prints a version
rive --help                             # ✅ lists commands
RIVE_ANALYTICS=off rive doctor          # ✅ exit 0; version/auth/project checks listed (auth warn ok if signed out)
```

### Phase 1 — Scaffold
```bash
cd <workspace>
rive create demo                        # ✅ creates demo/ with rive.yaml, scene.rml, AGENTS.md, .gitignore
cat demo/AGENTS.md                      # ✅ agent instructions exist — READ THIS before authoring
```

### Phase 2 — Static verification (no window)
```bash
rive demo --verify                      # ✅ exit 0 fresh scaffold
rive demo --verify --format=json        # ✅ JSON on stdout: success=true, command="verify", data.riv=null
rive demo --once                        # ✅ writes demo/build/demo.riv; exit 0
rive demo --screenshot                  # ✅ writes demo/build/demo.png (dark rect) — note path is CWD-relative when custom
rive inspect demo --json                # ✅ resolved scene JSON; artboards listed
```

### Phase 3 — Lookup tooling (the agent's "docs brain")
```bash
rive docs --list                        # ✅ topic list
rive docs layout                        # ✅ topic content
rive docs --search artboard             # ✅ matching lines
rive schema --list                      # ✅ all type names (or picker — force list via RIVE_NO_TUI=1)
rive schema Artboard                    # ✅ properties table
rive schema --search opacity            # ✅ search hits
```

### Phase 4 — Samples + headless capture
```bash
rive samples --path                     # ✅ prints samples dir
cp -R "$(rive samples --path)/rml_triangle" tri && rive tri --verify   # ✅ exit 0
rive tri --screenshot=shots/tri.png --advance=1   # ⚠️ must mkdir shots first (CWD-relative) — then ✅
rive tri --screenshot=shots/wide.png --viewport=900x600
rive tri --screenshot=shots/narrow.png --viewport=320x700   # ✅ responsiveness contrast
```

### Phase 5 — Interactivity proof (toggle pattern from docs)
```bash
rive demo --screenshot=shots/rest.png
rive demo --screenshot=shots/on.png  --pointer=click@120,60 --advance=20
rive demo --screenshot=shots/off.png --pointer=click@120,60 --advance=1 --pointer=click@120,60 --advance=20
# ✅ rest ≠ on; off ≈ rest (frame between clicks is mandatory)
rive demo --screenshot=shots/drag.png --pointer='drag@200,300>200,80:12'   # ✅ quoted drag
```

### Phase 6 — Data binding & dumps
```bash
rive demo --screenshot=shots/full.png --data=battery/level=100   # unmatched path → warning, exit 0
rive demo --data-dump                   # ✅ build/<name>.data.json (1.0.3 run used `--data-dump --once` — invalid, §15 item 3)
rive demo --data-dump=- --data-dump-filter='*' | head     # ✅ JSON to stdout (drop the `--once` the 1.0.3 run used)
```

### Phase 7 — Tests & benchmark
```bash
cp -R "$(rive samples --path)/tests_demo" td
rive td --test --format=json            # ✅ exit 0; passed>0, failed=0
rive td --bench=600                     # ✅ advance/render stats + WASM memory growth
```

### Phase 8 — Negative paths (CLI robustness)
```bash
rive demo --frame=5                     # ✅ exit 2, error names --advance
rive demo --verify --once               # ✅ exit 2 (two build modes)
rive demo --format=json                 # ✅ exit 2 (json without build mode)
rive demo --pointer=wiggle@1,1 --screenshot=shots/x.png   # ✅ exit 1/2 (unknown gesture)
rive demo --advance=-5 --screenshot=shots/x.png           # ✅ exit 2 (negative advance)
rive demo --bogus                       # ✅ exit 2 — unrecognized flags rejected
rive inspect /tmp                       # ✅ exit 1 (no rive.yaml)
```

### Phase 9 — Live preview (manual/optional, needs a window)
```bash
rive demo                # opens window; edit scene.rml, save → rebuild+reload
# in-window: s (screenshot) · p (pause) · f (fit) · z (size) · ? (help)
```

### Phase 10 — Auth-gated (optional; requires browser login)
```bash
rive login && rive whoami               # ✅ identity shown
rive demo --publish                     # may be watermarked until bound via `rive push`
rive logout && rive whoami              # ✅ exit 3
```

---

## 14. Agent authoring loop (recommended cadence)

```
edit scene.rml / *.luau
  → rive <dir> --verify --format=json     (fast compile gate; parse data.problems)
  → rive <dir> --screenshot --advance=1   (visual gate)
  → rive inspect <dir>                    (structure gate: ids, artboards, bindings)
  → repeat per stage: wireframe → structure → content → detail
```

Type questions go to `rive schema <Type>` (`--bindable` for data binding, `--animatable` for keying).
Workflow/how-to questions go to `rive docs <topic>` / `rive docs --search <text>`.

---

## 15. Live test results (rive 1.0.3, macOS arm64, 2026-09-16)

All 10 phases of the test plan (§13) were executed for real. Everything above is confirmed working. Differences found between the docs and the actual CLI — **trust these over the docs**:

1. **`rive push` exists now** (the older web docs said "coming soon"). Listed in `rive --help`; `rive docs push` covers push and pull. This entry records the 1.0.3 test, not a remaining limitation.
2. **`rive create` also writes `CLAUDE.md`** (imports AGENTS.md) — not just `AGENTS.md`.
3. **`--data-dump` is its own build mode**, not a modifier: combining it with `--once` exits 2 with `use only one of --verify, --once, --publish, --test, --screenshot, --semantics, --data-dump`. Run `rive vm --data-dump=-` alone.
4. **Unrecognized flags are now rejected** — `rive demo --bogus` exits **2**, not 0. The docs' "silent flag" quirk is fixed.
5. **`--test` exit code is 6** on failures (matches docs; `--help` text says exit 1 — docs/win).
6. `--advance` also works with `--data-dump` and `--semantics` (help text: "needs --screenshot, --semantics or --data-dump") — broader than the docs' "requires --screenshot".
7. Two extra undocumented samples ship: `integrated_titlebar`, `keyboard_menu` (10 total, incl. README).
8. Extra documented-but-not-in-web-docs flags observed: `--semantics`, `--semantic-action` (accessibility captures); `inspect` supports `--summary` (problems + object counts by type) and `schema` supports `--json` (both mentioned by the generated AGENTS.md).
9. Bench output (`bench advance/render/memory` lines) goes to **stderr**, not stdout.
10. **Compiler errors print on stderr with a `[timestamp] error` prefix; human summary line also stderr.** With `2>/dev/null` you see nothing — keep stderr when debugging.

### 15.1 Authoring traps hit during the live build (all confirmed the hard way)

These cost real debugging time; the docs warn about most of them, now proven:

- **`FontAsset` must be a ROOT element** (sibling of `<Artboard>`, near the root of the file). Nesting it inside the Artboard compiles clean, inspects clean, and renders **no text at all** — zero errors anywhere. Symptom: panel/shapes render, all text invisible.
- **Draw order is REVERSE of file order: the first-declared child paints in FRONT.** A background panel declared first will silently cover every sibling after it. The `pointer_reactive` sample's comment "Declared first, so it draws in front" is the rule. List children front-to-back: overlays first, background last.
- **Duplicate `id` attributes are a hard error** (exit 1, `duplicate id "0:12"`), and easy to hit when reusing ids from a scaffold after edits. Keep a mental (or real) id map per file.
- **A `Number` VM property cannot drive a `TextValueRun`** without a converter, and there is no number→string converter (`DataConverterToNumber` is the wrong direction; `DataConverterFormula` is random-based, not expressions). Use a **`ViewModelPropertyString`** bound to the run's `text` (propertyKey **268**) via `DataBindContext` — verified working, and the host can set it via `--data=temperature=105°`.
- Malformed XML (e.g. a self-closed run that also has children) gives a clear error: `<TextValueRun> is never closed, or is closed by a different tag`.
- `rive docs <topic>` + `rive docs --search` are genuinely good — the workflow "never guess a type or property, look it up" works; `propertyKey` values come from `rive schema <Type>` (`text` = 268 on TextValueRun; x/y = 13/14 on Node; rotation = 15).

### 15.2 Deliverable produced by the live run

`weathercard/` — the official example prompt (rounded panel, city name, temperature bound to a view-model property, animated rain icon), authored entirely via the agent workflow: `rive create` → `rive docs`/`rive schema` lookups → RML authoring → `--verify` → `--screenshot --advance` iteration → `--data` binding check → `--once` build (`weathercard/build/weathercard.riv`, ~395 KB incl. font).

Screenshots from the whole test run are in `shots/` (scaffold, triangle sample at 3 viewports, pointer hover/drag, weather card at multiple frames and with overridden data).

---

## 16. CLI 1.2.0 changes (release 2026-09-26; ✅ = verified live 2026-09-26, 📄 = from release notes / `rive docs`, not live-tested)

### Web publishing — new flags (all on `rive <project-dir>`)
| Flag | Effect |
|---|---|
| `--publish=web` ✅ | Build, sign, upload a **hosted page**, print its URL. **Goes live INSTANTLY — no confirmation prompt** when logged in. Also leaves the local signed `.riv` in `build/` |
| `--unpublish=web [--name=<n>]` ✅ | Take the page down (`--yes` skips confirm). Verified: prints `deleted <slug>`, exit 0; name frees up |
| `--list-published[=local\|web]` ✅ | Bare: one row per target (`local built …` / `web published <url>` / `web not published`) |
| `--team=<id>` / `--name=<name>` / `--no-wait` | Page belongs to a workspace; `--team` skips the picker, `--name` overrides the slug (default `pages.name` in rive.yaml, then project name), `--no-wait` prints URL without waiting for go-live |

⚠️ **Agent trap (verified the hard way):** `--publish=web` while logged in publishes immediately — a scratch "test build" ships to a public URL (`<slug>-<hash>.rive.to`). Use `--verify`/`--once` locally; if it happens, `--unpublish=web --yes` undoes it. Config lives under `pages:` (`teamId`, `name`) in `rive.yaml` — remove the block to be asked again.

### Other 1.2.0 behavior
- ✅ `--publish --quiet` now prints the written `.riv` path **on stdout** (also appears in the log stream) — scripts capturing stdout get the path instead of an empty string.
- ✅ `--fullscreen` is **in the release notes but NOT in the shipped 1.2.0 binary** — `unknown flag "--fullscreen"`, exit 2 (checked bare and with `--screenshot`). Release notes overshot the build.
- 📄 `rive push` now patches changed objects **in place, keeping ids** (before: delete+recreate, so the Editor lost keyframes/layers/states on open files). Removed properties reset to default; removed objects and type changes still delete. Pushed images now carry width/height from PNG/JPEG/WebP/KTX2 headers.
- 📄 Expired sessions now say `Not logged in. Run: rive login` on the first try (was `refresh failed (HTTP 400)`).
- 📄 Published projects whose scripts aren't declared in markup now run on the web (signature no longer silently disables every script).
- ✅ `rive.yaml` `window:` block (icon on every desktop: `label` ≤3 chars / `color` / `artboard` to draw one / `false`; macOS-only: `titleBar: integrated`, `controls.x/y`, `dragHeight`) and `cursor:` (native cursor opt-in via a bound VM property). Full detail: `rive docs project/rive-yaml`. Headless runs ignore `window:` entirely.
- 📄 RML: grid layouts, layout participants for shapes/text/images, Solos in layouts. `rive inspect` flags misplaced `GridTrack`/`LayoutParticipant`.
- 📄 `rive create` scaffold + docs now declare the state machine BEFORE timelines (✅ confirmed in generated `scene.rml`) — the Editor opens Animate mode on the first-listed.
- 📄 Keyboard/gamepad now work in the viewer on Windows; docs mark state-machine inputs deprecated in favor of view-model properties.
- ✅ Unchanged on 1.2.0: exit-code ladder (`--bogus`=2, `--format=json` w/o mode=2, two modes=2), `--verify --format=json` envelope, `--screenshot --advance`, `--pointer=click@x,y`, watermarking without `push.fileId`, docs topics.

---

## 17. CLI 1.3.0 changes (release 2026-10-02; ✅ = verified live 2026-10-02, 📄 = release notes / `--help` only, not live-tested)

### Account in the terminal (all need `rive login`; flags ✅ from `--help`)
| Command | Effect |
|---|---|
| `rive ls [projectId [folderId]]` ✅ | Projects → folders → files with ids. `--all` every file + folder path · `--recent` last 30 days · `--plain` table · `--json` one object/line · `--workspace=<id>` for one run. TTY: interactive browser (arrows/enter/typing filter; on a file: open in editor \| create local project \| print id); piped, agent context, Windows, or `RIVE_NO_TUI=1` prints instead. Docs: `rive docs push` |
| `rive workspace [<id>]` ✅ | Show current + other workspaces; with id, switch (personal until switched) |
| `rive open <fileId>` ✅ | Open in web editor + print url; `--print` url only; `RIVE_EDITOR_BASE` overrides editor host (pair with `RIVE_API_BASE`) |
| `rive whoami` 📄 | Now names the current workspace on a second line |
| `rive uninstall --unused` 📄 | Remove every cached version except in-use + default (installer builds only; Homebrew still refuses) |

### Scripting
- ✅ **Text works in Luau scripts** (≤1.2: no API, Font opaque): `context:font(name)` (font **assets**, not blobs; nil if missing), `Text.new()` + `:append(str, {font=, size=, paint=})` with `sizing`/`maxWidth`/`align`, `text:draw(renderer)`. Runtime shapes and orders glyphs — RTL (Arabic) reads correctly without script-side work. Verified: `scripted_text` sample `--verify` + `--screenshot` clean on 1.3.0. Docs: `rive docs luau/api/text`.
- 📄 `context:gpuTarget()` — script GPU pass draws into Rive's own target, under all content; not sampleable, starts each frame empty (first pass must clear/cover); nil where the host can't expose it → keep `GPUCanvas` fallback. Docs: `luau/api/gpu`.
- 📄 `event.type` in node `pointerDown/Move/Up/Exit` reports the real event (was always `"pointerEnter"`); `print("a", 1)` logs `a<TAB>1` (was `a1`).

### RML / build behavior
- ✅ `StateMachineLayer` with only an `EntryState` verifies green on 1.3.0 (≤1.2: layer didn't import). 📄 Missing `AnyState`/`ExitState` are added at build and their ids written back to markup (write-back not observed under `--verify`/`--once` — likely `rive push`; untested, no login). Docs: `rive docs format`/`gotchas`.
- 📄 State-machine inputs and listeners inside a folder now export (≤1.2: silently dropped with `0 errors, 0 warnings`, taking everything referencing them — blend states driven by them mixed nothing).
- 📄 A reference to a non-exported object now **fails the build** (≤1.2: dropped, build passed). Error names both ends: `TranslationConstraint targetId="0:12" targets a Node that is not exported.` — former silent-drop class became a hard error. Not in `rive docs`.
- 📄 Path winding comes only from `isClockwise`; `pathFlags` ignored and computed at build like the editor (≤1.2: viewer read `pathFlags`, disagreement could hide a path).
- 📄 `DataConverterEnumToUint` no longer exported, matching the editor (≤1.2: runtime skipped it, shifting every later converter one place → binds landed on the wrong converter). `rive inspect` reports `editor-only-converter` and points to `DataConverterToNumber`.
- 📄 `rive inspect` new diagnostic: `scripted-path-effect-not-under-paint` — a `ScriptedPathEffect` belongs inside `Fill`/`Stroke`/`GroupEffect`, not directly under `Shape` (≤1.2: file failed to load with a re-import error; docs showed the wrong placement, since fixed).
- 📄 `ListenerViewModelChange` takes `inputValue` (`pointerX`, `keyPressed`, `gamepadAxis`, …) and `inputValueIndex` for gamepad button/axis — the markup side of Editor 0.9.46 listener values. **Not in `rive docs` as of 1.3.0.**

### Viewer / headless
- 📄 Scroll views (`ScrollConstraint`) scroll with wheel/trackpad, incl. horizontal strips nested in vertical lists; `wheelInteractive="false"` opts out per view (not in docs). New `scroll_demo` sample ✅ present.
- 📄 macOS: bare Shift/Control/Option/Command reach scripts and keyboard listeners; keys held on focus loss are released everywhere (no more stuck keys).
- 📄 Headless `--key` with nothing before it now reaches the element the entry state focuses (≤1.2: went nowhere, logged `key: nothing is focused, so no listener will see this`).
- ✅ Unchanged on 1.3.0: exit-code ladder, `--verify --format=json` envelope, `--screenshot --advance`, scaffold shape (SM still declared before timelines, Any/Exit/Entry still emitted), generated `AGENTS.md` still a lean workflow doc.

---

## 18. CLI 1.4.0 changes (release 2026-10-08; ✅ = verified live 2026-10-08, 📄 = release notes / `--help` / docs only)

### Libraries come with the project 📄
- `rive create --from-remote-file` and `rive pull` now download EVERY library the file imports (nested included) into `.libraries/`, and list the direct ones under `libraries:` in `rive.yaml`. Before 1.4.0: such a project failed to build and the viewer showed nothing.
- A library that fails to download leaves its parts out (as in the editor) instead of stopping the build. `rive push` still pushes only your project.
- Commit `.libraries` so teammates build without pulling; never edit inside it — the next pull replaces it. `override: ../palette` on a library entry makes the build use that local project instead (edit library + consumer together, no publish round trip); `rive pull` keeps the override. Docs: `rive docs project/libraries-folder`.

### Android / device preview & app shipping (flags ✅ from `--help`; behavior 📄)
- `rive . --android[=<name>]` — install the Rive player on the first connected Android device, or pick by adb serial / emulator name (starts arm64 emulators that aren't running; offers to download Google's platform tools when adb is missing). Every save pushes a new build. Multitouch works — each finger is its own pointer. Draws with Vulkan by default; `--device-backend=gl` switches to OpenGL. Not on Windows yet.
- Related: `--device=<name>`, `--ios`, `--serve[=port]`, `--headless-serve`.
- `rive build [dir]` — ships the project as an app of its own and installs it on a connected device (see §4 row for flags).

### Headless input (✅ live)
- `--touch=<kind[:id]@x,y>` — synthesise a finger: `down|up|move|tap`; each `id` is its own pointer (default 0; a lift is also its exit). `drag@x1,y1>x2,y2+x3,y3>x4,y4[:steps]` moves several fingers in the same frames — pinches and two-finger swipes. Verified: `--touch=tap@250,250 --advance=1` capture, exit 0.
- `--pointer` gains `wheel@x,y:dx,dy` and `trackpad@x,y:dx,dy[:steps]` (`-y` reveals what is below; the swipe then flings; a trackpad swipe ends in the same fling every run, so captures match).
- Unconsumed scroll now SAYS so instead of silently capturing a never-moved list — verified: `wheel: nothing at 250,250 scrolled. No scroll view under it can move that way, or its wheelInteractive is off`.

### Keying by name (✅ live)
- `<KeyedProperty property="x">` — keyframes address their target by **property name**, resolved on the type of the object the `KeyedObject` animates (`rive docs format` §Animation). `rive pull` / `--from-rev` / `--from-remote-file` markup now writes names (`blendModeValue="softLight"` instead of `"21"`, `property="rotation"` instead of `propertyKey="15"`). Hand-written names work; give name or number, or both only if they agree.
- Unknown name = BUILD error (exit 1) with a suggestion — verified: `Node has no property "xx" to animate; did you mean "x"?`. Numeric form still compiles — verified: `propertyKey="13"` (x) green.

### fetch in scripts (✅ live; limits 📄)
- `fetch(url, options?) -> Promise<Response>` in Luau (and AnimaScript). Response: `status`, `statusText`, `ok`, `url`, `headers`, `text()`, `arrayBuffer()`, `header(name)`. Options: `method` (GET HEAD POST PUT PATCH DELETE OPTIONS), `headers`, `body`, `timeout` (default 30s, cap 60s). Docs: `rive docs luau/api/net`.
- Requires `rive <dir> --allow-net`. Without it every request rejects with `disabled: network access is not enabled for scripts in this host` (verified). With it, verified live: `FETCH_OK status=200` from `https://example.com/`.
- 📄 https only; IP addresses, local-network names and Rive's own hosts refused; size/timeout/per-minute limits; macOS only for now. Loading a downloaded `.riv`: `context:decodeFile(bytes)` + `file:bindableArtboard(name)` → assign to a VM artboard property; only its embedded assets load.
- Related script flags ✅(`--help`): `--aot` (ahead-of-time compile, here and on devices); `--optimize` (now described as AnimaScript dropping its debugger line probes, running several× faster — for timing and long tests); `--define=NAME[=n]` (AnimaScript build constants; overrides `rive.yaml` defines); `--debug[=port]` (VS Code script debugger — 📄 the extension adds a View Models panel and Break on Value Change).
- 📄 `--bench=<frames>` now compiles scripts the way a publish does (before: timed the preview build, lower optimization).

### Luau generator annotation is LOAD-BEARING (✅ live; not stated in `rive docs luau/protocols`)
- A protocol script must return a generator **with** the protocol's return annotation — `return function(context: Context): Layout<T>` for a `ScriptedLayout`; `Node<T>` / `PathEffect<…>` / `Converter<…>` / `ListenerAction<T>` / `TransitionCondition<T>` / `Interpolator` for the other `Scripted*` elements. Without it: `--verify` GREEN, the `.riv` builds, the screenshot writes — and the script NEVER runs. Only hint: a raw, **untimestamped** line (not the usual log format), printed twice at load: `ScriptAsset doesn't have a generator function <name>`. `rive inspect` shows `generatorFunctionRef: 0` for working samples too — inspect is NOT the tell; the load line is. Live-reproduced on `ScriptedLayout` only (`text_rain` annotation strip); the other six protocols are generalized expectation, not yet tested.
- Isolated live: `text_rain` sample runs clean; stripping only the `: Layout<Rain>` annotation from its return line brings the error back.
- Once annotated, strict types enforce the whole contract: state needs a named `type X = {...}` and the returned table must match EXACTLY (ad-hoc fields like a `done` flag must be declared in the type); `advance` must return `boolean` (true = redraw me).
- Adjacent type-check traps hit on the way: colon methods double-declare `self` (`function T:m(self: T)` → lint error — use `function T.m(self: T, …)` or assemble local functions into the literal); `async(fn)` rejects a void-returning callback (`Expected this to be 'T', but got '()'`) — use `promise:andThen(onOk, onErr)`.

### RML / scripting / viewer (📄)
- `<Stroke position="inside|center|outside">` — default center, written only when it differs; runtimes without support draw centered (Early Access in the editor).
- `pointerScroll(self, event)` script method takes wheel/trackpad scroll; `event:hit()` keeps it, otherwise it passes to the scroll view behind. Scripts without it never take scroll.
- Every 2D vector a script receives now has `z = 0` (before: leftover values made `length()` too long and `==` sometimes false).
- WGSL uniform structs accept `mat2x2f`–`mat4x4f`, their `h` forms, and `vec2h`–`vec4h`.
- Viewer fixes: a trigger fired by a nested state machine reaches every listener; a transition now sees a value a listener action just wrote (the "button needed two clicks" class); COLRv1 emoji draw gradients; text inputs behave like platform fields; virtualized scrolling works in grid and wrapping layouts (both directions).
- AnimaScript lane (docs ✅): `.as` = TypeScript-syntax language compiled to wasm by the CLI's `rasc`; same protocol bases (Layout/Node/PathEffect/Converter/ListenerAction/TransitionCondition/Interpolator) attached with the same `Scripted*` elements; `rive docs animascript/protocols` + `animascript/api/*`; samples `*_as`.

### Unchanged on 1.4.0 (✅ live)
- Exit ladder: `--bogus`=2, `--format=json` without mode=2, two build modes=2. The two-modes message now names the full exclusive set (editor, `--verify`, `--once`, `--publish`, `--unpublish`, `--list-published`, `--test`, `--screenshot`, `--semantics`, `--data-dump`).
- `--verify --format=json` envelope identical; `--screenshot --advance`; `--pointer=click` ordering rules; `--data-dump`.
- Scaffold (1.4.0 template): `scene.rml` still SM-before-timelines with Any/Exit/Entry emitted and `defaultStateMachineId` set; `AGENTS.md` still the lean workflow doc (now also warns: don't preview via `rive push`; no HTML/web-runtime preview — unsigned scripts are rejected); `rive.yaml` = name + logs only; `.gitignore` excludes `build/` only (so a downloaded `.libraries/` would be committed, matching the release note).
