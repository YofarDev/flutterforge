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

## 1. Plan, then apply

The app must be a git repo with a clean tree. If it is not, ask the user to
commit or stash; do not do it for them.

```bash
uv run --no-project <template>/.agents/skills/flutterforge-upgrade/prepare_upgrade.py --template <template> --dry-run
```

The helper rebuilds what the generator shipped at BASE (what the app came
from: `.flutterforge.json`, else the best file match) and at HEAD, then
classifies every file the template changed against the app's copy:

| Action | Meaning | On apply |
| --- | --- | --- |
| `take` | app still has the base version | replaced by the template's |
| `merge` | both changed it, edits don't overlap | 3-way merged |
| `CONFLICT` | both changed the same lines | written with `<<<<<<< app` / `>>>>>>> template` markers |
| `add` | new template file where the app has that area | created |
| `delete` | template deleted it, app never changed it | deleted |
| `keep` | template deleted it, app changed it | left alone — review |
| `skip` | new file with no place in the app (missing feature/folder) or importing something the app won't have | not written |
| `absent` | template changed a file the app removed or moved | not written |

Show the user the plan. Check the base line: if the match count is low or the
user knows the real base, rerun with `--base <rev>`. Then run without
`--dry-run`: it writes the plan on a new branch `flutterforge-upgrade-<sha>`,
stages and commits nothing, and records the new base in `.flutterforge.json`.

**Diverged apps.** When under 25% of the base template files are unchanged in
the app, the report says `DIVERGED` and nothing is written. Such an app has
replaced template conventions (its own error type instead of fpdart, its own
DI layout, its own generator). Either port the plan's `take`/`add` items by
hand, or rerun with `--apply-diverged` and resolve every `CONFLICT` and
`merge` under the convention rule below — always with the user's agreement.

## 2. Resolve conflicts — the app's conventions win

**Rule:** when the app replaced a template convention, keep the app's version
of everything built on that convention (generators, feature templates, wiring
files, error handling) and port only the template changes that do not depend
on it (flags, output, speed, docs). Never introduce a convention the app
dropped (e.g. fpdart `Either` code into an app without fpdart).

| File kind | Resolution |
| --- | --- |
| Tooling the app never customized (`take`) | Already the template's version — nothing to do. |
| Tooling the app customized: `scripts/`, `scripts/feature_templates/`, `test/support/architecture_checker.dart` | Keep the app's version; hand-port convention-free improvements from the template side. Skip helpers the app's own generator does not use (e.g. `fwire.py` when the app kept its own `fgen.sh`). |
| Shared docs/config: `AGENTS.md`, `README.md`, `analysis_options.yaml`, `l10n.yaml` | Keep both: the app's project rules plus the template's new rules, minus text the template removed. |
| App code: `lib/`, `test/` | Keep the app's code. Take a template change only when it is infrastructure the app now needs. |
| `add` files | Check each one fits the app (e.g. a test of a core file the app does not use); delete what does not. |
| `delete` / `keep` | Confirm with the user any deletion of something the app may still use. |

Resolve every marker (`git diff --check` and `grep -rn '<<<<<<< app'` find
leftovers).

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
