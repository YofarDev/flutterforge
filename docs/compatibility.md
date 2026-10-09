# Compatibility and verification policy

This document records what the FlutterForge generator and its generated apps
are verified against, and the policy for changing any of it. The executable
counterpart of this document is `scripts/verify_template.sh` (see
[Testing the template](../README.md#testing-the-template)).

## Verified baseline

| Component   | Baseline                  | Notes                                           |
| ----------- | ------------------------- | ----------------------------------------------- |
| Flutter SDK | 3.47.4 (stable channel)   | The version the October 2026 review verified against. CI pins this lane. |
| Dart SDK    | 3.13.3                    | Ships with Flutter 3.47.4.                      |
| uv          | any recent (≥ 0.12 verified) | Required by `fstr`/`fl10n`/`fimp`/`remove_counter.sh` and the root test harness. |
| Bash        | ≥ 3.2 (macOS stock)       | See the shell contract below.                   |
| OS          | macOS (arm64) and Linux   | Both exercised in CI (macOS: baseline lane only). |

A separate **current-stable** CI lane runs the full smoke suite against the
latest stable Flutter to detect compatibility drift. The pinned baseline lane
passing does **not** demonstrate latest-stable compatibility; only that lane
does.

## Shell contract (Bash 3.2, portable helpers)

Every script shipped by this repository (`scripts/*.sh`, `remove_counter.sh`,
`scripts/verify_template.sh`) must run under **macOS's stock Bash 3.2** — no
`mapfile`/`readarray`, no namerefs (`local -n`), no assuming Bash 4+ handling
of empty arrays under `set -u`, and no quoted heredoc inside a `$( )` command
substitution (a Bash 3.2 parser limitation when the heredoc body contains
quotes or parentheses — `fl10n.sh` redirects to a temp file for this reason).

The contract is enforced, not just documented:

- `scripts/verify_template.sh` syntax-checks every shipped script with the
  system Bash before running any test.
- The fast harness level executes representative helpers (`fdead.sh`,
  `fl10n.sh`) under `/bin/bash` on fixture apps (on macOS that is the real
  3.2.57; on Linux it is whatever the system Bash is, still a full parse and
  run).

Do not "fix" a script by requiring a newer Bash: either port the construct or,
if a script genuinely needs Bash 4+, that is a compatibility-policy change
that must be reflected here and in `scripts/verify_template.sh`'s check.

## Dependency policy

`packages_to_add.json` expresses every dependency generated apps need as a
**major-version-constrained spec** (`package:^major.minor` form), e.g.
`freezed_annotation:^3.0.0`. The rules:

- Ranges are established empirically — by running `flutter pub add` in a
  disposable app with the verified SDK and encoding the resolved majors —
  never guessed and never frozen to exact versions.
- The required **major** version is pinned because the template's code (and
  generated features) are written against those API generations (e.g. freezed
  v3 annotations with `sealed`, bloc_test v10, go_router 18). This blocks
  silent major upgrades during ordinary generation.
- Minor/patch drift is allowed; each generated app keeps its own normal
  `pubspec.lock`.
- Transitive dependencies are never pinned by hand.
- The full smoke suite archives the smoke app's resolved `pubspec.lock` so the
  actually-tested dependency set is inspectable after the fact.

Changing a range: re-establish it empirically on the verified baseline (and
the current-stable lane), update this table, and let the smoke suite regenerate.

| Package            | Spec                    | Resolved when established |
| ------------------ | ----------------------- | ------------------------- |
| flutter_bloc       | `^9.0.0`                | 9.1.1                     |
| go_router          | `^18.0.0`               | 18.0.2                    |
| freezed_annotation | `^3.0.0`                | 3.1.0                     |
| json_annotation    | `^4.12.0`               | 4.12.0                    |
| get_it             | `^9.0.0`                | 9.3.0                     |
| fpdart             | `^1.0.0`                | 1.2.0                     |
| flutter_lints      | `^6.0.0` (dev)          | 6.0.0                     |
| bloc_test          | `^10.0.0` (dev)         | 10.0.0                    |
| mocktail           | `^1.0.4` (dev)          | 1.0.5                     |
| build_runner       | `^2.16.0` (dev)         | 2.16.1                    |
| freezed            | `^4.0.0` (dev)          | 4.0.1                     |
| json_serializable  | `^6.0.0` (dev)          | 6.14.1                    |
| analyzer           | `^13.0.0` (dev)         | 13.3.0                    |
| path               | `^1.8.0` (dev)          | 1.9.1                     |
| intl               | `any` (added by the generator, alongside `flutter_localizations` from the Flutter SDK) | — |

## Minimum-version change policy

- The **verified baseline Flutter version** changes only deliberately: bump
  the pinned CI lane, regenerate the smoke evidence, and update this file in
  the same change. The current-stable lane may break before the baseline is
  moved — that is its purpose.
- The **minimum supported Flutter version** for generated apps is implicitly
  the verified baseline; older SDKs are untested and unsupported.
- Tool prerequisites (`uv`, Bash) follow the same rule: change the
  requirement, the up-front check in `scripts/verify_template.sh`, and this
  document together.

## CI

> **Status:** the workflow below has been added and validated locally only
> (fast suite + full smoke run on the local machine). It has **not yet run
> remotely** on GitHub Actions; remote CI results are not yet evidence.

`.github/workflows/template-verification.yml` runs on pull requests and on
pushes to `main` (the repository's default branch):

- **fast** — Linux, the fake-tool generator/refusal/shell-contract suite
  (~seconds).
- **smoke** — the full real-Flutter suite on three lanes: Linux pinned
  3.47.4 baseline, Linux current stable, macOS pinned baseline. Jobs are
  read-only (`permissions: contents: read`), time out after 60 minutes, and
  superseded runs are cancelled. On failure, the smoke artifacts (logs,
  Flutter/Dart versions, template git revision, resolved generated
  `pubspec.lock`) are uploaded.

## Verification levels (local)

```bash
./scripts/verify_template.sh          # fast: fake tools, seconds
./scripts/verify_template.sh --full   # + real-Flutter smoke suite, minutes
```

The full level generates real apps in unique temporary directories outside
this checkout, exercises every `fgen` combination, applies the documented
DI/route wiring for a generated feature, removes the counter feature (twice),
checks for unresolved placeholder package names, runs skill synchronization
in check-only mode, and records versions/revision/lockfiles. Failures retain
their logs.

Both levels run from plain script invocations — no aliases, editor hooks, or
personal PreToolUse interceptors are assumed. The template root has no
`pubspec.yaml` by design (it is a generator/template source, not an app), so
template checks always run either against fake tools or through disposable
generated apps — never by treating the repository itself as a Flutter project.
A generated app compiling is necessary but not sufficient: it does not by
itself prove that routes or DI registrations work; the smoke suite's wiring
and flow-test steps exist to check exactly that.
