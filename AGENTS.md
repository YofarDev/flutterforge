# Agent starting point

- Before choosing tooling, read the command catalogue: [README.md → CLI Tools](README.md#cli-tools) in a generated app, or [template-README.md → CLI Tools](template-README.md#cli-tools) in the FlutterForge template repository.
- Use the repository-local commands below from the project root. Personal shell aliases (`fgen`, `fstr`, etc.) are optional and must not be assumed to exist.
- Read the project-local [flutter-architecture skill](.agents/skills/flutter-architecture/SKILL.md) when adding a feature or refactoring. Also read [flutter-testing](.agents/skills/flutter-testing/SKILL.md) when writing tests, [flutter-audit](.agents/skills/flutter-audit/SKILL.md) for deep reviews, and [flutter-bloc-provider](.agents/skills/flutter-bloc-provider/SKILL.md) for provider errors or dialog/sheet provider boundaries.
- `.agents/skills/` is the canonical skill source; edit it rather than optional synchronized copies.

# Available tools

These commands are included in generated apps. Select the tool relevant to the task; advisory scans do not replace verification or manual review.

| Command | When to use it | File effects / constraints |
| --- | --- | --- |
| `./scripts/fverify.sh` | Before finishing any app change. | Checks formatting, analyzes, and runs tests; never fixes source. Prepare explicitly as described below. |
| `./scripts/fgen.sh feature_name [--with-service] [--with-dto]` | Add a new feature. | Writes a lean scaffold, translations, and generated code; refuses existing feature directories. Wire DI/routes and tests afterward. |
| `./scripts/fstr.sh keyName "French" "English"` | Add a localization key. | Updates both ARB files and regenerates localization; use matching placeholders and a new key. |
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
- **Radio**: `groupValue` and `onChanged` are deprecated (after v3.32.0) → use a `RadioGroup` ancestor to manage group value instead
- Run `./scripts/fverify.sh` before finishing any app change — it runs a `dart format` **check** (never rewrites files), then `flutter analyze` + `flutter test`; fix everything it reports.
- Resolve dependencies and regenerate localization/Freezed/JSON outputs when needed before analysis (`flutter pub get`, `flutter gen-l10n`, `dart run build_runner build --delete-conflicting-outputs`). Preparation before verification is always explicit: run `dart fix --apply` and `dart format .` yourself in every runtime. Do not assume a user-level hook will do it for you.
- `test/architecture_test.dart` (via the analyzer-based checker in `test/support/architecture_checker.dart`) enforces the layering rules on statically-visible dependencies: inward deps, domain purity through local re-export chains (including reached generated libraries and all conditional branches), no cross-feature internals (public barrels only), acyclic feature dependencies, core ↛ features, no cubit-to-cubit fields, getIt access limited to the composition roots, registrations only in `service_locator.dart`. It cannot see dynamic coupling — that remains review guidance. Keep it green and extend it (with a negative fixture) when a rule is added to the skills.
