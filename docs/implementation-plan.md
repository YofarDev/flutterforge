# FlutterForge implementation handoff

This plan implements the recommendations from the October 8, 2026 review. It is intended for an agent working in small, independently verified phases. The requested deliverable is an improved generator, its generated app template, its tests, and its agent instructions. Preserve the existing Flutter/Cubit/get_it/go_router/Freezed/fpdart stack.

## 1. Read this before implementing

### Repository model

- This repository is a generator and template source, **not a runnable Flutter app**. It intentionally has no root `pubspec.yaml`.
- `create_project.dart` runs `flutter create`, copies the template, installs packages listed in `packages_to_add.json`, generates code/localizations, and runs `scripts/fverify.sh`.
- `lib/`, `test/`, and `scripts/` contain source that is copied into generated applications. Tests placed in `test/` must work in generated applications.
- `.agents/skills/` is the canonical source of project skills. Use `scripts/sync_skills.sh` to update existing `.codex/skills/` copies after editing canonical instructions. Do not sync to user-level folders as part of this work.
- Root-level generator tests belong in a new `tools/` directory. They must not be copied into applications or recursively call themselves through app verification.
- Read `AGENTS.md`, `flutter-architecture`, and `flutter-testing` before code changes. Use the current repository implementations as the starting point; do not regenerate the entire repository from another template.
- Use jcodemunch and Context7 when available as required by the repository instructions. If unavailable, record that limitation and use local source searches and official package documentation.

### Confirmed review evidence

Using Flutter 3.47.4 and Dart 3.13.3, the reviewer verified that:

1. Fresh project creation passes analysis and tests.
2. Generating a feature and removing the counter example both leave an app passing `fverify`.
3. Rerunning project creation on the same destination deletes an added `lib/` file.
4. Rerunning `fgen` for an existing feature overwrites an edit.
5. Completing a HomeCubit request after `close()` throws a StateError.
6. An older HomeCubit response can overwrite the result of a newer request.
7. A domain file importing its own data layer, and a nullable stored cubit field, both pass the complete existing verification gate.

Reproduce defects using disposable projects, never an existing user application. Do not rely on the reviewer's temporary files remaining available.

### Scope and implementation constraints

- Implement phases in order. Commit-sized changes are preferred; do not commit or push unless the user separately requests it.
- Keep the root generator executable with `dart create_project.dart`; do not require adding a root Flutter app just to test the template.
- Keep existing supported CLI usages working, except intentional rejection of unsafe destinations and the documented lean-default change to `fgen`.
- Do not add overwrite/force flags. Updating an existing application is a separate future migration feature.
- Do not add a generic base cubit, event bus, automatic retry framework, or multi-package workspace.
- Do not replace all mocks. Use mocks for isolated tests and real components with fake I/O for feature-flow tests.
- Preserve counter behavior, including its documented settings-failure fallback, unless a change is explicitly specified below.
- Edit generator/template sources, not only a generated scratch app. Never copy a scratch app's whole `lib/` or `test/` tree back: that would bring generated files and substituted package names with it.
- Keep `my_flutter_app` placeholders in template test imports; generated projects substitute their actual package name.
- Add dependencies to generated apps with `flutter pub add`. Update the template's `packages_to_add.json` to express packages that future generated apps need. Do not hand-edit a generated `pubspec.yaml` to add dependencies.
- Use `uv run` for Python execution and `fstr`/`scripts/fstr.sh` for localization additions.
- For template localization changes, run `fstr` inside a generated scratch app, verify generation there, then copy only the reviewed ARB changes back to the template. The root cannot run Flutter localization generation without an app pubspec. Do not copy generated localization Dart files back.

### Verification procedure for every phase

1. Run narrowly targeted regression tests first.
2. Generate a fresh disposable app from the current template into a new directory outside this checkout, with `--no-open` and an explicit platform.
3. In the generated app, run code generation if needed, `dart fix --apply`, `dart format .`, then `bash scripts/fverify.sh`.
4. Inspect fixes: if they change handwritten template code, apply the corresponding source correction to this repository and regenerate. A repaired scratch app alone is not a passing template.
5. Keep command logs, SDK versions, and exit codes. Report failures honestly; do not disable rules, drop assertions, or exclude affected files to obtain a green result.
6. Inspect `git diff` for unrelated edits and generated artifacts.

Baseline example (use a unique parent directory each time):

```sh
audit_parent=$(mktemp -d)
cd "$audit_parent"
dart /absolute/path/to/flutterforge/create_project.dart --no-open --platforms=linux audit_app
cd audit_app
dart fix --apply
dart format .
bash scripts/fverify.sh
```

The platform flag creates platform files; this procedure does not claim to build or launch a Linux app on macOS. Unit/widget verification requires no emulator.

## 2. Phase A — Protect generator destinations

**Priority:** first. **Risk:** low to medium. **Goal:** invalid input and retries cannot overwrite user work.

### Files

- `create_project.dart`
- `scripts/fgen.sh`
- New `tools/test_template.py` for generator/CLI regression tests
- `README.md` and `template-README.md` for CLI contracts

### Project creation

1. Separate destination path from Dart package name. The package name is the validated final directory component, or the explicit Flutter `--project-name` value if supported. Never substitute a filesystem path into package imports.
2. Make argument parsing deterministic. Support the documented `--org=value`, `--org value`, `--no-open`, `--platforms=value`, destination, and standard forwarded Flutter options. Correctly handle option values after the positional destination. Reject ambiguous/multiple destinations before invoking Flutter. Preserve a supplied `--description` rather than replacing it unconditionally.
3. Preflight the destination before `flutter create`: reject an existing file, directory, or symlink, including an empty directory or dangling symlink. Reject the template root. Do not delete or modify the existing target.
4. Validate required template files and required executable availability before creating output. Ensure the template source is resolved from the script location, independently of the caller's working directory.
5. Create a uniquely owned staging directory under the destination's parent, and pass an explicit valid project name to `flutter create`. Complete generation and verification there before publishing the directory at its final name. Recheck the final destination before publishing. Document that this protects ordinary retries, not concurrent writers to the same destination; do not claim a portable atomic no-clobber guarantee without implementing one.
6. Delete or retain only staging files owned by this invocation on failure. Prefer retaining a failed staging directory with its path and diagnostic output. Never recursively delete a caller-supplied existing directory.
7. Open VS Code only after successful publication and only when `--no-open` is absent.
8. Restrict placeholder substitution to copied template-owned text paths. Do not recursively rewrite SDK metadata, dependency caches, or unrelated platform files.
9. Stream subprocess output, or at least print command progress and all failure output. Preserve nonzero exit codes. Keep this a small CLI improvement, not a new process framework.

Staging changes the project path. Test the published app from its final directory too: rerun package resolution as needed to refresh path-dependent metadata, then verify it there. Do not announce success solely because tests passed before the directory moved. If final-path validation fails, retain the newly generated output with a clear error; do not delete it or touch another destination.

### Feature generation

1. Resolve the app root deliberately from the current directory/ancestors; fail when no application `pubspec.yaml` and expected template structure exist. Remove the fallback to `my_flutter_app` when no project exists.
2. Accept a documented name format. Preserve valid snake_case and existing camelCase-to-snake_case normalization, then validate the normalized name and generated Dart identifier. Reject empty values, separators, `..`, punctuation, invalid starting characters, and Dart reserved identifiers.
3. Compute all output paths before writing. Reject if either the target feature directory or its test directory already exists, including symlinks. Never partially overwrite an existing feature.
4. Quote filesystem paths throughout the script.
5. Render new source into an owned temporary directory first. Publish only after validation. If subsequent code generation fails, report the incomplete new feature and exit nonzero; do not erase unrelated app changes while attempting rollback.

### Required tests

- A normal project name, custom organization, and `--no-open` succeed.
- Absolute and relative destination paths use the correct package name; parent paths containing spaces work.
- Existing directory with sentinel files, empty directory, existing file, and symlink are refused without changing content.
- Rerunning project generation preserves edits and exits nonzero.
- Rerunning feature generation preserves source and test edits and exits nonzero.
- Invalid feature names and execution outside an app write nothing.
- A subprocess failure returns nonzero and never reports setup complete.
- Supported argument orderings produce the intended destination and metadata.
- The published app resolves dependencies and passes verification from its final path, after staging has moved.

Use real subprocess smoke tests for successful generation. Fast refusal tests may use controlled fake executables to assert Flutter was not invoked, but do not mistake these for testing successful Flutter creation.

**Done when:** ordinary retries cannot overwrite source, output paths and package names are distinct, and the successful workflow still passes verification.

## 3. Phase B — Make async state updates deliberate

**Risk:** medium. **Goal:** disposal and response ordering have tested semantics.

### Files

- `lib/features/home/presentation/bloc/home_cubit.dart`
- `lib/features/counter/presentation/bloc/counter_cubit.dart`
- Cubit template inside `scripts/fgen.sh`
- Existing home/counter cubit tests; generated cubit tests

### Home and generated read operations

1. Use latest-request-wins for `initialize`/`refresh`/generated `loadData`.
2. Add a private monotonically increasing request identifier. Each accepted request captures its identifier before awaiting.
3. Return without emitting when invoked after close. After awaiting, return when closed or when the request identifier is stale. Check before processing either a success or a failure result.
4. Keep the current visible loading/success/failure lifecycle. A superseded failure must not replace a newer success.
5. Explain that ignoring a stale result does not cancel its network request. Add transport cancellation only when an actual data source needs it.
6. Keep this logic local to the cubits; do not introduce a base class for two small methods.

### Counter operations

- Preserve one increment/decrement per accepted action. Do not apply latest-request-wins to writes indiscriminately.
- Check closure before starting and after settings retrieval.
- Define reset as invalidating pending pre-reset increments/decrements. A simple generation counter captured by each operation and advanced by `reset()` is sufficient for the current example.
- Multiple increments without an intervening reset must all apply, reading current count when their settings lookup completes.
- Retain and test the existing fallback to default settings when retrieval fails.
- Document that this example does not provide an ordered persistent-write queue; future noncommutative writes need serialization or another explicit policy.

### Required tests

Use controllable `Completer`s and fake dependencies, not real sleeps:

- Success and failure completing after close do not emit or throw.
- Two reads completed in reverse order retain the newer request's result.
- A stale failure cannot overwrite a newer success.
- A failed current request is followed by a successful retry.
- Two counter increments are both applied.
- Reset invalidates an earlier pending counter operation.
- Counter settings failure follows the documented fallback.
- The emitted scaffold carries these protections and its corresponding tests.

**Done when:** all lifecycle tests pass and the generator no longer teaches the unsafe async pattern.

## 4. Phase C — Keep failures typed through presentation state

**Risk:** medium. **Goal:** localization and UI behavior use failure type, while diagnostics stay out of user messages.

### Files

- `lib/core/models/failure.dart`
- New `lib/core/errors/exception_mapper.dart`
- New `lib/core/l10n/failure_localization.dart`
- Home/counter repository implementations and repository tests
- Home state, cubit, screen, and their tests
- Corresponding state/cubit/repository/screen sections of `scripts/fgen.sh`
- Localization ARB files through `fstr`

### Implementation

1. Keep the existing failure categories: server, network, unauthorized, unexpected. Remove the UI-oriented `Failure.message` getter. Do not add speculative categories.
2. Make `Failure` a pure immutable model. Move exception classification and logging out of its static `fromException` method into the infrastructure mapper. This removes its transitive dependency on the Flutter logger.
3. Log error and stack trace at the repository mapping boundary, then return a typed failure. Preserve timeout-to-network and unknown-to-unexpected behavior. Malformed DTO conversion must produce a failure rather than escape as an exception.
4. Optional diagnostic fields on failures may be retained for compatibility, but must never be automatically displayed. Remove diagnostics from test fixtures that were only simulating UI copy.
5. Change `HomeState.failure` and generated error states to carry `Failure`, not `String`.
6. Map failures exhaustively to `AppLocalizations` in the presentation-side localization helper. Its imports may include the failure model and generated localization class, but must not introduce presentation dependencies into domain models.
7. Add English/French keys through `fstr`: network failure, unauthorized, server failure, unexpected failure. Reuse an existing appropriate key rather than creating duplicates.
8. Update `HomeError` and generated screens to localize at build time. Do not put BuildContext into cubits or domain services.
9. Replace logging references to `failure.message` with structured/category-oriented logging. Avoid duplicate logging of the same exception across layers.
10. Allow the application to follow the device locale rather than unconditionally forcing English. Keep both supported locales. Do not add locale preferences/state management in this phase.

### Required tests

- Repository success mapping, timeout classification, unknown exception classification, and malformed date/JSON data.
- Cubit failure state retains the failure category.
- English and French rendering of every failure category.
- Diagnostic exception strings and server diagnostic details are absent from rendered UI.
- Changing locale updates an existing error state's displayed message.
- Retry behavior remains operational.

**Done when:** domain/state code owns error meaning, presentation owns text, and failure paths remain fully tested.

## 5. Phase D — Strengthen executable architecture boundaries

**Risk:** medium to high; keep this phase focused. **Goal:** rules are syntax/type-aware and the checker has its own regression tests.

### Files

- `test/architecture_test.dart`
- New `test/support/architecture_checker.dart`
- New `test/architecture_checker_test.dart`
- Fixture definitions under `test/support/` as source strings or non-`.dart` fixture assets
- `packages_to_add.json`: add `analyzer` as a direct dev dependency; add `path` if directly used

### Implementation approach

Use the compatible analyzer API actually installed in the generated app. Consult its current API before implementing; do not guess visitor or element APIs from memory. Parse directives/fields with the AST and resolve types where needed for cubit inheritance and aliased service-locator usage.

Separate the checker from its filesystem/test runner. Return structured violations containing a rule identifier, source path, line, and explanation. Test fixture projects must supply package configuration so the checker can distinguish app imports from external packages. Do not silently ignore failed source resolution: report an actionable checker error.

### Rules to enforce

| Rule | Required behavior |
| --- | --- |
| Inward dependencies | Presentation cannot import data; domain cannot import data or presentation; data cannot import presentation. |
| Domain purity | Domain cannot depend on Flutter UI libraries, generated localizations, router, DI, theme, or the logger. Pure shared models and approved Dart packages remain allowed. |
| Cross-feature access | Other features can depend only on an explicitly designated public domain contract, not arbitrary domain internals or data/presentation files. |
| Public contract convention | Use `lib/features/<feature>/<feature>.dart` as an optional public barrel; it may expose domain contracts/models/services only. No need to create empty barrels for unrelated demo features. |
| Infrastructure | Core does not import feature internals except designated composition roots. |
| Stored state controllers | Production components cannot store Cubit/Bloc dependencies, including nullable, late, mutable, generic/container, aliased, or inherited cubit types. Local widget callback reads are allowed. |
| Locator access | Registration is owned by `lib/core/di/service_locator.dart`; resolution is limited to `lib/app.dart` and `lib/core/router/app_router.dart` plus registration wiring. Feature classes use constructors. |
| Bootstrap | `lib/main.dart` may call setup/bootstrap and `runApp`; it must not become a second dependency-registration site. |

Explicitly allow app.dart to compose app-scoped providers and import their presentation types. The existing test's two-root exemption is too narrow for the documented app composition pattern.

Normalize filesystem paths and resolve relative and same-package `package:` URIs to the same app file identity. Inspect import, export, and conditional-directive targets. Validate public barrel exports so they cannot re-export data or presentation to bypass the rule. Check generated files only according to an explicit policy: normally exclude generated implementation files, while checking all handwritten imports and declarations.

Avoid exceptions based on naming alone, such as treating every file called `service_locator.dart` as privileged. Keep exact relative-path allowlists.

### Required checker tests

Each rule needs both allowed and forbidden examples. Include:

- Own-domain-to-own-data import in relative and package syntax.
- Cross-feature data/presentation imports and a barrel that leaks them.
- Allowed cross-feature public domain contract and rejected direct domain-internal import.
- Nullable, late final, mutable, aliased, generic, and unusually named Cubit subclasses stored as fields.
- Allowed local `context.read<...>()` reference inside a widget callback.
- Feature-level direct or aliased `getIt`/`GetIt.instance` resolution rejected; constructor injection accepted.
- Valid DI/router/app composition and main bootstrap accepted.
- Conditional imports, path normalization, and multiline syntax.
- A malformed/unresolved fixture produces a clear checker failure rather than a false pass.

Fixtures must not be live broken `.dart` files inside the generated app's analyzed source tree. Do not solve fixture analyzer errors by broadly excluding production directories.

Keep the checker scoped to statically visible dependencies. Do not claim it can detect every dependency hidden behind `dynamic`, callbacks, or runtime service resolution. Runtime ownership and behavior still need flow tests and review. Resolve one analysis context per fixture/app rather than rebuilding it for every file so the quality gate remains practical.

**Done when:** the two previously reproduced violations fail the architecture gate, the checker itself has meaningful negative tests, and allowed real app patterns stay green.

## 6. Phase E — Make scaffolding proportional to feature complexity

**Risk:** medium. **Goal:** offer a lean default with explicit optional layers.

### CLI contract

```text
fgen.sh <feature>                         # lean default
fgen.sh <feature> --with-service           # add domain coordination seam
fgen.sh <feature> --with-dto               # separate transport/domain representation
fgen.sh <feature> --with-service --with-dto
```

Document the changed default. Do not require a migration of features already generated with the full layout.

### Default generated structure

- Domain immutable model without unnecessary JSON serialization.
- Domain repository interface.
- Data source interface plus placeholder implementation as the external-I/O seam.
- Repository implementation using typed results and the exception mapper.
- Cubit depending directly on the repository interface.
- State and screen with the lifecycle and localization behavior from phases B/C.
- Repository, cubit, and essential widget tests.

Without `--with-dto`, the placeholder data source may return the domain model directly; do not pretend it represents a real transport schema. With `--with-dto`, generate the transport model, serialization, conversion, and mapping tests. If the example DTO differs only trivially, explain which future transport concerns justify the option.

With `--with-service`, insert the service dependency and generate its tests. State clearly that the placeholder service should gain actual rules/coordination or be removed; a forwarding service is not mandatory architecture.

### Existing demo adjustments

- Simplify HomeCubit to depend on `IHomeRepository`; keep trimming the welcome message as an explicit presentation transformation. Remove the now-redundant HomeService and its forwarding tests, update DI and all affected tests.
- Retain CounterService because it owns actual step/bounds behavior.
- Keep the home transport/domain distinction: the DTO timestamp string converts to a domain DateTime and is a useful real mapping example.
- Preserve meaningful existing example DTOs; this is not a blanket removal of serialization or domain models.
- Generate a single screen widget when a Screen merely forwards to a View with no distinct responsibility. Do not reorganize every existing widget solely for naming consistency.

### Generator integration

- Keep DI and route changes explicit: print correct instructions for each option combination, using the new public APIs and lifetimes. Do not add fragile source-string surgery to silently register arbitrary features.
- Generate required screen localization keys through the established helper, after checking for key collisions before writes. Produce no hardcoded English error prefixes.
- Scaffold repository failure tests, not only cubit and forwarding-service tests.
- Explain that an unregistered scaffold passing unit tests is not a routed feature. The smoke harness must apply and test the documented wiring.

### Required tests

Generate all four option combinations with distinct feature names. Verify intended files/dependencies, run codegen and `fverify`, wire at least the lean and full variants into test composition, and exercise loading/failure/retry. Rerun collision/refusal tests after modifying the generator.

**Done when:** a simple feature has fewer unnecessary layers, complex features can opt in, and every mode produces verified source and meaningful tests.

## 7. Phase F — Add real feature-flow and behavior tests

**Risk:** low to medium. **Goal:** prove components work together across the boundaries.

### Files

- `test/app_test.dart`
- New `test/features/home/home_flow_test.dart`
- Home/counter repository, cubit, and widget tests
- `lib/core/router/app_router.dart`, `lib/app.dart`, and DI setup only as needed for isolation

### Implementation

1. Add a widget-level flow test with a fresh router, real HomeCubit, real repository, and a controllable fake data source. After phase E there is no HomeService; retain a real CounterService in the counter flow.
2. Give each test an independent router that is disposed afterward. Prefer a router factory and explicit app injection/default ownership rather than reusing the static router across every test. Do not create a new router on every build.
3. If necessary, let DI setup accept narrow data-source overrides for tests. Keep registrations in the single composition module; do not duplicate the entire application dependency graph inside widget tests.
4. Await asynchronous getIt reset/disposal and cubit shutdown in teardown.
5. Test home loading to success, failure to localized retry to success, and navigation to counter/back with route-scoped state recreated according to policy.
6. Include disposal with pending work in the integrated flow, supplementing the focused cubit tests.
7. Test representative non-default counter settings through the real service. Cover malformed repository input and fallback behavior without duplicating the implementation in mock callbacks.
8. Keep useful isolated mock/fake cubit widget tests. Name widget flow tests accurately; they are not device-level integration tests or proof of a platform build.

**Done when:** actual navigation, provider lifetimes, localization, and the real feature dependency chain are tested together without network or sleep-based timing.

## 8. Phase G — Automate generator and compatibility verification

**Risk:** medium. **Goal:** the template repository can prove the product it generates works.

### Files

- Expand `tools/test_template.py`
- New `scripts/verify_template.sh`
- New `.github/workflows/template-verification.yml`
- New `docs/compatibility.md`
- `scripts/fverify.sh`, `README.md`, `template-README.md`, `test/README.md`

### Harness design

Use Python standard-library unittest/subprocess/tempfile, invoked with `uv run`, unless a compelling existing test harness is discovered. Avoid introducing a root application package just for orchestration.

Provide two documented levels:

- Fast generator refusal/input tests, with deterministic fake commands where appropriate.
- Full smoke verification using the real installed Flutter SDK, unique temporary paths, bounded subprocess timeouts, and retained logs on failure.

The full workflow must:

1. Generate a clean app from current template sources and verify it.
2. Exercise all feature-generation options.
3. Apply the documented DI/route instructions for representative generated features in the disposable app, then test resolution/rendering. A narrowly scoped fixture patch in the harness is acceptable; don't turn the production CLI into a regex patch engine.
4. Verify refusal of existing project/feature destinations and preservation of sentinel contents.
5. Remove the counter from an otherwise fresh generated app and verify again. Test repeated removal as a harmless operation or explicitly documented refusal; it must not damage the remaining app.
6. Check generated imports contain no unresolved placeholder package name.
7. Run skill synchronization in check-only mode.
8. Record Flutter/Dart versions, template Git revision, and resolved generated `pubspec.lock` in the test report/artifacts.

### SDK/dependency policy

- Start the verified baseline at Flutter 3.47.4, the version used in the review, after confirming CI can provision it.
- Run a separate current-stable lane to detect compatibility drift. Label it accurately; an older pinned lane does not demonstrate latest-stable compatibility.
- Use dependency ranges compatible with the template's actual APIs, including required major versions. Avoid unconstrained silent major upgrades during ordinary generation.
- Establish ranges using `flutter pub add` in a disposable app and encode supported specifications in `packages_to_add.json`. Do not guess package versions or freeze every transitive dependency manually.
- Each generated app retains its own normal application lockfile. Archive the smoke app lockfile so the tested dependency set is inspectable.
- Document supported SDK/platform/tool prerequisites and the policy for changing the minimum supported version.

### CI

- Run on pull requests and the repository's actual default branch; inspect its name rather than guessing.
- Run full smoke tests on Linux for the pinned baseline and current stable.
- Add a macOS baseline lane for generator/script portability if the repository's CI allowance supports it; otherwise document that limitation rather than claiming coverage.
- Install Flutter and uv explicitly. Do not depend on personal aliases, global skills, VS Code, or user hooks.
- Check the documented shell prerequisite. The current `fdead.sh` uses `mapfile`, which fails under macOS's stock Bash 3.2. Either make shipped helpers portable to that shell or explicitly require/provision a newer Bash and check it up front; test the chosen contract. Do not claim native macOS portability just because a developer has Homebrew Bash first in PATH.
- Upload logs and resolved dependency metadata on failure. Apply job timeouts and cancellation of superseded runs.
- Verify against official action/package documentation at implementation time. Use read-only repository permissions for verification jobs.

### App verification behavior

Keep `fverify` non-mutating. Add a format check after first bringing handwritten sources into compliance, followed by analysis and the full tests. Codegen prerequisites must be explicit. Keep autofix/format as an intentional preparation action, not a hidden CI mutation. Template verification and app verification must have distinct names and must not recursively invoke each other.

**Done when:** one documented root command validates the generator, and CI reproduces the workflow without the author's machine configuration.

## 9. Phase H — Align instructions and documentation with reality

**Risk:** low. **Goal:** agents receive consistent, accurate guidance matching the verified implementation.

### Files

- `AGENTS.md`
- `.agents/skills/flutter-architecture/SKILL.md` and `examples.md`
- `.agents/skills/flutter-testing/SKILL.md` and companions
- `.agents/skills/flutter-audit/SKILL.md`
- Corresponding existing `.codex/skills/` copies via sync
- `README.md`, `template-README.md`, `test/README.md`, `docs/compatibility.md`

### Required changes

1. Replace “main.dart contains runApp only” with “main performs bootstrap and runApp; dependency registrations have one owner.” Match the composition-root exceptions implemented by the checker.
2. Replace the blanket “real repositories in tests are wrong” rule with a distinction: isolated tests mock dependencies; feature-flow tests use real components over fake external I/O.
3. Document lean scaffolding and optional domain services/DTOs, with concrete criteria for adding each.
4. Document request ordering, disposal checks, reset invalidation, and stream/subscription cleanup. Explain that async read cancellation and write ordering are different decisions.
5. Document typed failures and presentation-side localization. Update all snippets using string failure states or `Failure.message`.
6. Distinguish hard dependency rules from preferences. A single BlocListener is fine; use MultiBlocListener to flatten multiple listeners. Widget rebuild scope and extraction need judgment rather than blanket bans.
7. Explain precisely which architecture rules are executable and which remain review guidance. Remove claims that a passing regex/checker suite proves all architecture rules. Negative checker tests are part of the contract.
8. Update examples to compile against supported dependency versions, use explicit types, close owned resources, and match the actual APIs. For stream examples, await asynchronous subscription cancellation.
9. Correct the testing skill's `testGoldens` example if only built-in flutter_test is installed: use the supported `testWidgets` API with `matchesGoldenFile`, or explicitly declare a real optional dependency. Do not add a golden-test package just to preserve a misleading snippet.
10. Clarify logger usage as actual static AppLogger methods; a standalone generator CLI can use stdout/stderr without importing Flutter logging.
11. Distinguish root `verify_template.sh` from generated-app `fverify.sh`. Explain that template root has no pubspec and checks must run through disposable generation.
12. Remove the dependency on implicit personal analyze hooks from the documented quality gate. Keep preparation commands explicit and verification behavior consistent across agents.
13. Update paths, script lists, test descriptions, and supported prerequisites. Remove references to nonexistent commands such as `findstr.sh` unless it is actually supplied.
14. Describe `sync_skills.sh --check` honestly: it currently skips missing target skill directories. Either make missing required copies fail or explicitly document optional targets; do not announce universal synchronization after silently skipping required copies.

Run local skill sync, then `--check`. Never run `--user` or edit installed user-global skills for this task.

**Done when:** instructions, scaffold output, tests, and documentation describe one consistent architecture and workflow.

## 10. Final acceptance and agent completion report

Before declaring completion:

- [ ] Existing-target and invalid-input cases are non-destructive and tested.
- [ ] Fresh creation succeeds with verified package-name/path handling.
- [ ] All four feature-scaffold combinations pass verification.
- [ ] Representative generated features are actually wired and exercised.
- [ ] Counter removal leaves a verified app.
- [ ] Async disposal, stale reads, retry, reset, and repeated actions are tested.
- [ ] Failures retain their type and render correctly in English and French without diagnostic leakage.
- [ ] Architecture positive/negative fixtures cover the enforced rules and fail closed on checker errors.
- [ ] Real-component feature-flow tests cover navigation and lifetimes.
- [ ] Root smoke verification runs without personal hooks/aliases and records resolved versions.
- [ ] Required CI configuration, compatibility policy, and synchronized instructions are present.
- [ ] No generated app artifacts, local caches, sentinel files, credentials, or unrelated global changes entered the repository diff.

The implementation agent's final response must list completed phases, commands/results, any deviations with reasons, and remaining limitations. If CI has not actually run remotely, say the workflow was added and locally validated; do not claim remote CI passed. A scaffold compiling alone is not evidence that its route or DI registration works. If a phase is blocked, report its exact blocker and preserve the passing earlier phases.

Suggested execution order is A → B → C → D → E → F → G → H. Tests that reproduce each phase's defects should land with that phase, not wait until phase G. Update directly affected instructions as needed during implementation, then perform the full consistency pass in H.
