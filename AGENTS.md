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
- Run `fverify` before finishing any change (`./scripts/fverify.sh` if the alias is missing) — it runs a `dart format` **check** (never rewrites files), then `flutter analyze` + `flutter test`; fix everything it reports. Run `dart fix --apply` and `dart format .` yourself beforehand — the documented gate does not rely on any personal editor hooks or aliases.
- To add a localization string, run `fstr $keyName "$stringFr" "$stringEn"`
- You can run `fl10n` (no arguments) to find hardcoded user-facing strings that still need localizing (review each finding, then add keys with `fstr`)
- You can run `fimp` (no arguments) to auto-fix broken internal imports
- You can run `fdead` (no arguments) to find orphaned files
- You can run `fgen $feature_name` to generate the boilerplate when adding a new feature
- Preparation before `fverify` is always explicit: run `dart fix --apply` and `dart format .` yourself in every runtime. Do not assume a user-level hook will do it for you.
- `test/architecture_test.dart` (via the analyzer-based checker in `test/support/architecture_checker.dart`) enforces the layering rules on statically-visible dependencies: inward deps, domain purity, no cross-feature internals (public barrels only), core ↛ features, no cubit-to-cubit fields, getIt access limited to the composition roots, registrations only in `service_locator.dart`. It cannot see dynamic coupling — that remains review guidance. Keep it green and extend it (with a negative fixture) when a rule is added to the skills.
- Read skill `flutter-architecture` whenever you add a feature or refactor.
