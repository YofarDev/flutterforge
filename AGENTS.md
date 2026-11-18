# Agent starting point

- The table below is the complete tool catalogue; do not read the README to choose a tool. Open [README.md → CLI Tools](README.md#cli-tools) (generated app) or [template-README.md → CLI Tools](template-README.md#cli-tools) (template repository) only when a tool's exact arguments or failure behavior matter.
- Use the repository-local commands below from the project root. Personal shell aliases (`fgen`, `fstr`, etc.) are optional and must not be assumed to exist.
- Read the project-local [flutter-architecture skill](.agents/skills/flutter-architecture/SKILL.md) when adding a feature or refactoring. Also read [flutter-testing](.agents/skills/flutter-testing/SKILL.md) when writing tests, [flutter-audit](.agents/skills/flutter-audit/SKILL.md) for deep code reviews, [mobile-ux-audit](.agents/skills/mobile-ux-audit/SKILL.md) for hands-on UI/UX audits of a running app, [flutter-bloc-provider](.agents/skills/flutter-bloc-provider/SKILL.md) for provider errors or dialog/sheet provider boundaries, and [flutter-widget-refactor](.agents/skills/flutter-widget-refactor/SKILL.md) for widget/presentation-layer cleanups that must not change behavior, and [flutterforge-upgrade](.agents/skills/flutterforge-upgrade/SKILL.md) to update this app to a newer FlutterForge template.
- `.agents/skills/` is the canonical skill source; edit it rather than optional synchronized copies.

# Available tools

These commands are included in generated apps. Select the tool relevant to the task; advisory scans do not replace verification or manual review.

| Command | When to use it | File effects / constraints |
| --- | --- | --- |
| `./scripts/fmap.sh` | Start of a session, before exploring files. | Read-only: one line per feature (routes, wiring, layers, barrel dependencies). Orientation only. |
| `./scripts/ftest.sh [paths] [--slowest[=N]]` | Running tests: with paths while iterating (`./scripts/ftest.sh test/features/<f>/`), never a bare `flutter test`. `--slowest` before optimizing a slow suite. | Machine-wide queue shared with every project (scoped runs use a separate light lane), niced runs, each compile error printed once. A full run (no paths) compiles test files into a few parallel shards (files in a shard share an isolate — tests must not leak global state; ~30% faster on a 260-file suite, 2–4× on small ones) and skips the architecture gate when `lib/` is unchanged since its last green run (always runs on CI or with `FORGE_ARCH_ALWAYS=1`). `fverify.sh` runs its tests through it. `FORGE_QUEUE=0` disables the queue, `FORGE_TEST_AGGREGATE=0` the shared isolate. |
| `./scripts/fverify.sh --fix` | Before finishing any app change. | Runs `dart fix --apply` + `dart format` (source dirs: `lib`, `test`, … — never `build/`), then the gate (format check, analyze, tests); refuses to apply `dart fix` when it would touch more than 25 files (an SDK migration — decide on it separately). Without `--fix` it is the same gate and never rewrites source (CI uses that form). Passing tests print nothing. |
| `./scripts/fgen.sh feature_name [--with-service] [--with-dto]` | Add a new feature. | Writes a lean scaffold with its module, barrel, tests and translations, and wires the module into DI, router and the DI test at the `// fgen:` markers; refuses existing feature directories. |
| `./scripts/fstr.sh key "French" "English" [key "French" "English"]...` | Add localization keys. | Updates both ARB files once and regenerates localization once; pass several triples in one call. Placeholders must match; keys must be new. |
| `./scripts/fl10n.sh` | Find hardcoded user-facing strings. | Read-only scan; review findings, then add keys with `./scripts/fstr.sh`. |
| `./scripts/fimp.sh` then `./scripts/fimp.sh --apply` | Investigate and repair broken imports. | Preview writes nothing. Apply repairs static URI tokens; edits remain if analysis or unresolved repairs cause failure. Review proposals first. |
| `./scripts/fdead.sh` | Investigate potentially unreferenced files. | Advisory, read-only scan; never deletes files and cannot prove deletion is safe. |
| `./scripts/fcheck.sh [package_name]` | Review dependencies or one package's direct imports. | Advisory, read-only inventory; inspect indirect usage, exports, code generation, assets, and platform channels before removal. |
| `./scripts/fanal.sh [project_path]` | Gather leads for an architecture/code audit. | Writes or overwrites `flutter_analysis.md`; findings are heuristic and require source review. |
| `./scripts/sync_skills.sh --check` / `./scripts/sync_skills.sh` | Check skill drift / synchronize edited canonical skills. | Check is read-only; sync updates matching skills in existing optional project targets. `--user` also targets existing user-level copies; use only when that scope is requested. |
| `./remove_counter.sh` | Remove the untouched Counter demo from a freshly generated app when requested. | Deletes Counter files and rewrites demo wiring/tests. Review the diff and run the app quality gate afterward. |

Prerequisites: Bash and Flutter/Dart on `PATH`; `uv` is also required by `fgen`, `fstr`, `fl10n`, `fimp`, and `remove_counter.sh`. See the README catalogue for arguments, limitations, and failure behavior. `fimp.py`, `render_feature.py`, and `feature_templates/` are supporting assets invoked by the shell tools.

The FlutterForge template repository intentionally has no `pubspec.yaml`. Its own gate is `./scripts/verify_template.sh`; use `--full` for real generated-app smoke checks when changing generation or shipped tooling. Run app preparation and `./scripts/fverify.sh` inside a generated app. `verify_template.sh`, `tools/test_template.py`, and `personal_tools/` are template-repository tools and are not installed into generated apps.

# Python

- Always use `uv` instead of `python` for running Python scripts and managing packages
- Use `uv run` instead of `python` for executing scripts
- Use `uv pip` or `uv add` for package management instead of `pip`

# Flutter

- `flutter pub add <package>` (never edit pubspec.yaml manually)
- Always specify type annotations
- `withOpacity()` is deprecated → use `.withValues(alpha: ...)`
- Log with the static methods of `AppLogger` (e.g. `AppLogger.info('...', tag: '...')`) — never `print()` in app code. (`AppLogger` is a Flutter app utility; the template's standalone generator CLI, `create_project.dart`, correctly writes to plain `stdout`/`stderr` instead of importing Flutter logging.)
- **freezed v3**: Classes with factory constructors now require `sealed` or `abstract` keyword
- `@freezed` classes go in a `models/` or `bloc/` folder, `@JsonSerializable`/`fromJson` classes in `models/`: `build.yaml` runs codegen only there (one-file rebuilds take ~1 s instead of ~30 s). Elsewhere they get no generated part ("Target of URI doesn't exist: '….freezed.dart'"); move the class or extend `build.yaml`.
- **Radio**: `groupValue` and `onChanged` are deprecated (after v3.32.0) → use a `RadioGroup` ancestor to manage group value instead
- Run tests with `./scripts/ftest.sh <paths>` (only the affected area while iterating), never a bare `flutter test`: it queues behind other projects' runs on this machine.
- Run `./scripts/fverify.sh --fix` before finishing any app change — one command for `dart fix --apply`, `dart format` on the source dirs, then the gate (`dart format` check, `flutter analyze`, `flutter test`); fix everything it reports. Plain `./scripts/fverify.sh` is the non-mutating gate only.
- Resolve dependencies and regenerate localization/Freezed/JSON outputs when needed before analysis (`flutter pub get`, `flutter gen-l10n`, `dart run build_runner build --delete-conflicting-outputs`). Code generation is never run by the gate, and no user-level hook should be assumed to do it for you.
- `test/architecture_test.dart` (via the analyzer-based checker in `test/support/architecture_checker.dart`) enforces the layering rules on statically-visible dependencies: inward deps, domain purity (no Flutter UI, `dart:ui`, `flutter_bloc`/`bloc`, `go_router`) through local re-export chains (including reached generated libraries and all conditional branches), no cross-feature internals (public barrels only), acyclic feature dependencies, core ↛ features (every `lib/` folder outside `lib/features/`, e.g. `lib/shared/`, counts as core), every file under `lib/features/<f>/` is the barrel, the module or inside `data/`/`domain/`/`presentation/`, feature modules imported only by `service_locator.dart` and `app_router.dart`, part files in the same feature and layer as their library, no `file:` URIs, no stored cubit/bloc fields outside widgets (records, factories, `BlocBase`/`StateStreamable` and freezed fields included; a `Widget`/`State` may keep a cubit it receives), getIt access limited to the composition roots, registrations only in `service_locator.dart` and feature modules (`lib/features/<f>/<f>_module.dart`). It cannot see dynamic coupling — that remains review guidance. Keep it green and extend it (with a negative test) when a rule is added to the skills; the checker's own regression fixtures live in the FlutterForge template repository (`tools/checker_tests/`), not in generated apps.
