---
name: flutterforge-upgrade
description: Use when updating an existing Flutter app that was generated from the FlutterForge template to a newer template version. Triggers include "update this project to the latest template", "upgrade flutterforge", "sync template changes into my app", "pull the new scripts/skills into this project". Stages a 3-way merge of template-owned files, resolves conflicts while keeping the app's customizations, applies dependency changes, adopts opt-in code migrations, and verifies.
---

# Upgrade an app to a newer FlutterForge template

Goal: bring template-owned files (scripts, skills, `AGENTS.md`, `lib/core`
infrastructure, test support, CI) up to date **without losing the app's own
changes**. Never commit, push, or delete app-owned code without the user's OK.

## Inputs

- **Template**: a local checkout of FlutterForge. Ask for its path if the user
  did not give one; if they give a git URL, clone it into a temp directory. The
  target is the template's committed `HEAD` unless the user names a revision.
- **App**: the current project root (the directory with `pubspec.yaml`).

Old apps do not contain this skill or its helper; always run the helper from
the **template's** copy: `<template>/.agents/skills/flutterforge-upgrade/`.

## 1. Stage the merge

The app must be a git repo with a clean tree. If it is not, ask the user to
commit or stash; do not do it for them.

```bash
uv run --no-project <template>/.agents/skills/flutterforge-upgrade/prepare_upgrade.py --template <template> --dry-run
```

Read the report: base revision (and why it was chosen), template commits,
changed files, dependency changes. The base comes from `.flutterforge.json`
when present, otherwise from matching the app's files against every template
commit. If the match count is low or the user knows the real base, pass
`--base <rev>`. Then run the same command **without** `--dry-run`.

What it does: rebuilds exactly what the generator shipped at BASE and at HEAD
(same package name; Counter removal mirrored when the app removed the demo),
then cherry-picks BASE→HEAD into a new branch `flutterforge-upgrade-<sha>` with
`--no-commit`. Untouched files update, files the template deleted are deleted,
and files the app customized come back as ordinary merge conflicts. It also
writes `.flutterforge.json` so the next upgrade knows its base.

## 2. Resolve conflicts

List them with `git diff --name-only --diff-filter=U`. Per file:

| File kind | Resolution |
| --- | --- |
| Template tooling: `scripts/`, `.agents/skills/`, `test/support/architecture_checker.dart`, `test/architecture_test.dart`, `.github/workflows/flutter-ci.yml`, `remove_counter.sh` | Take the template side, then re-apply the app's change only if it was a deliberate customization. |
| Shared docs/config: `AGENTS.md`, `README.md`, `analysis_options.yaml`, `l10n.yaml` | Keep both: the app's project-specific rules plus the template's new rules. Drop text the template removed. |
| App code: `lib/`, `test/` (outside `test/support/`) | Keep the app's code. Port a template change only when it is infrastructure the app now needs (e.g. a new `core/` import). |
| modify/delete (app deleted a file the template changed) | Keep it deleted unless the app still needs it. Never resurrect demo code (Counter, placeholder Home content) the app removed or replaced. |

`git add` each resolved file; finish when `git diff --name-only --diff-filter=U`
is empty. Then review template deletions
(`git diff --cached --name-status --diff-filter=D`) and confirm with the user
any deletion of something the app may still use (e.g. personal scripts).

## 3. Dependencies and code generation

Run the `flutter pub add ...` commands the report printed (never edit
`pubspec.yaml` by hand). "pinned" lines need action only if the app's current
constraint excludes the new one. For "removed from template", remove the
package only if `./scripts/fcheck.sh <package>` and a manual check show it
unused. Then:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

## 4. Verify

Run `./scripts/fverify.sh --fix` and fix everything it reports. A newer
architecture checker may report violations the old one missed: fix the code,
never weaken the checker or delete architecture tests to get green. If a fix
needs a real restructuring (moving a feature, extracting a domain service),
stop and list it for the user instead of doing it unasked.

## 5. Adopt opt-in code migrations

The merge updates template files; it does not rewrite the app's own features.
Read `git -C <template> log --oneline <base>..<head>` and the notes below, and
apply what fits, smallest change first, re-running `fverify` after each:

- **`LatestRequestWins`** (`lib/core/bloc/latest_request_wins.dart`): replace
  hand-rolled `_requestId` latest-request-wins logic in cubits with
  `runLatest(...)`, then delete that cubit's stale-ordering and close-safety
  tests (the mechanism is tested once in core). Test fakes that
  `implements XCubit` must add `with LatestRequestWins<XState>`. Features
  generated by the new `fgen` already use it.
- **Leaner tests** (see `test/README.md`): delete framework/config tests,
  "renders X"/"provides X" tests and forwarding-service tests; move per-screen
  failure-copy assertions into the `localizeFailure` unit test.
- **Quiet tests**: `test/flutter_test_config.dart` turns `AppLogger` off
  during tests. If the app's `test/` already had its own config, merge the
  `AppLogger.enabled = false;` line into it.
- **Feature modules** (`lib/features/<f>/<f>_module.dart`): the merge brings
  the `// fgen:` markers into `service_locator.dart`, `app_router.dart`,
  `route_constants.dart` and the DI test only if the app had not customized
  those files; otherwise add the four markers by hand so `fgen` can auto-wire
  new features. Existing hand-wired features keep working; moving one into a
  module (registrations + routes) is optional and best done when touching it.
- **Public barrels**: add `lib/features/<f>/<f>.dart` exporting the domain
  models/contracts of any feature another feature needs.
- **fpdart imports**: generated code now uses `show Either, ...` so a feature
  named like an fpdart type (e.g. `order`) compiles; apply the same fix if a
  name clash appears.
- **One-command gate**: use `./scripts/fverify.sh --fix` instead of separate
  `dart fix` / `dart format` / `fverify` calls in any app docs or CI notes.

## 6. Report

State: base → head; each conflict and how it was resolved; deletions;
dependency changes applied; migrations done and skipped (with reason); the
final `fverify` result. Leave everything uncommitted on the upgrade branch
and offer to commit.

## Maintaining this skill

When a template change requires app-code migration, add a bullet to step 5 in
the same commit. Keep `prepare_upgrade.py` in sync with `create_project.dart`
whenever the generator's copied paths or substitutions change.
