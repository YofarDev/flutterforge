---
name: "flutter-audit"
description: "Use when the user wants a deep analysis, code review, audit, or incremental refactoring plan for an existing Flutter project. Triggers include: 'review my Flutter project', 'audit my codebase', 'what's wrong with my architecture', 'check my BLoC structure', 'analyze my Flutter app', 'refactoring plan', 'migrate my architecture', or when the user shares Flutter files/folders and asks for feedback. This skill checks compliance against flutter-architecture standards and produces a structured, actionable report with an incremental migration plan."
---

# Flutter Architecture Audit

Structured analysis against `flutter-architecture` standards. Produces a prioritized report
**plus an incremental migration plan** so the codebase can be improved safely, one step at a time.

**Always read `flutter-architecture` before auditing.**

---

## Step 1 — Pre-Analysis

Run `fanal` (in current folder) if available. It should summarize: file tree, feature map,
file sizes, cross-feature imports, DI wiring, cubit coupling, routing, and tests.

If `fanal` is unavailable, prefer `rg`; use `grep` only as a fallback.

```bash
# DI registrations vs composition roots
rg -n "BlocProvider\\(|Cubit\\(|Bloc\\(" lib -g '*.dart'

# Cubit-to-cubit / bloc-to-bloc dependencies
rg -n "final .*Cubit\\b|final .*Bloc\\b" lib/features -g '*.dart'

# Cross-feature imports into internals
rg -n "import .*features/.*/(data|presentation)/" lib/features -g '*.dart'

# Presentation importing data directly
rg -n "import .*data/" lib/features -g '*.dart'

# Provider boundaries worth auditing
rg -n "GoRoute\\(|Navigator\\.push|showDialog\\(|showModalBottomSheet\\(" lib -g '*.dart'
```

---

## Step 2 — Deep Analysis

### A. Cubit vs BLoC
For each `*_bloc.dart`: do explicit events improve clarity, auditability, or concurrency control?
Examples: debounce, throttle, restartable work, cancellation, droppable events, or multi-step workflows.

If the bloc is really just method calls plus `emit`, suggest Cubit.
**Do not require a custom `EventTransformer` to justify a BLoC.**

### B. State Exhaustiveness
Are sealed/freezed states handled exhaustively with `.when()`, `.map()`, or a Dart `switch` over the union?
Are there scattered `if (state is X)` checks duplicating UI branching logic?

```bash
rg -n "state is |\\.when\\(|\\.map\\(|switch \\(state\\)" lib/features -g '*.dart'
```

### C. Error Handling
Do repositories return `Either<Failure, T>` instead of leaking exceptions?
Do repository tests verify DTO-to-domain mapping and failure translation?
Do cubits/blocs emit typed failure states instead of swallowing errors?

### D. Presentation Scope
- `BlocBuilder` wrapping a full `Scaffold` without need?
- `BlocConsumer` used where separate `BlocBuilder` + `BlocListener` would be clearer?
- Nested `BlocListener`s instead of `MultiBlocListener`?
- Dialogs, sheets, routes, or pushed screens missing the provider boundary?
- `BlocProvider.value` used when reusing an existing cubit instance across a new subtree?

### E. Layer and Module Boundaries
- Presentation importing `data/` directly?
- Features importing another feature's `presentation/` or `data/` internals?
- Shared business logic forced into `core/` instead of a dedicated shared module/package or public contract?

### F. DI Integrity and Lifetimes
- Is there a single registration source of truth (`service_locator.dart` / `injection.dart`)?
- Do composition roots resolve from `getIt` instead of manually assembling graphs?
- Are route-scoped cubits created at the smallest sensible boundary?
- Are parameterized cubits using `registerFactoryParam` or another explicit factory path?
- Are singleton vs factory choices consistent with the intended lifecycle?
- Do any service registrations require `getIt<SomeCubit>()` or `getIt<SomeBloc>()` as constructor arguments?

### G. Cubit Coupling and Cohesion
- Any cubit with `final SomeCubit` / `final SomeBloc` as a field?
- Any service or repository with `final SomeCubit` / `final SomeBloc` as a field, or importing a feature `presentation/` layer?
- Coordination logic duplicated across multiple cubits instead of a domain service?
- Any feature over-split into micro-cubits with artificial coordination?
- Any single cubit carrying unrelated responsibilities with different reasons to change?

---

## Step 3 — Audit Report

### Flutter Architecture Audit — `[project name]`

#### Summary

| Category | Status | Issues |
|----------|--------|--------|
| Project Structure | ✅/⚠️/❌ | n |
| State Management | ✅/⚠️/❌ | n |
| State Design | ✅/⚠️/❌ | n |
| Error Handling | ✅/⚠️/❌ | n |
| Presentation | ✅/⚠️/❌ | n |
| DI Integrity | ✅/⚠️/❌ | n |
| Cubit Coupling | ✅/⚠️/❌ | n |
| Routing | ✅/⚠️/❌ | n |
| Models | ✅/⚠️/❌ | n |
| Standards | ✅/⚠️/❌ | n |

#### Critical Issues
Architecture violations that create hidden coupling, wrong lifecycles, or broken boundaries.

```text
[CATEGORY] Title
File: path/to/file.dart (line N)
Problem: What's wrong and why it matters.
Fix: Concrete code or step-by-step instruction.
Migration risk: low / medium / high
```

#### Warnings
Maintenance burdens that will compound if left in place.

#### Suggestions
Minor improvements and cleanup opportunities.

---

## Step 4 — Incremental Migration Plan

This section is the primary output when the user asks for a refactoring plan.
Each phase must leave the app compiling and running. Never propose a big-bang rewrite.

### Default phase order

1. **Registration and lifecycle integrity first** — fix dual wiring and wrong cubit scope before changing behavior
2. **Cubit decoupling second** — remove cubit-to-cubit dependencies via domain services
3. **Feature/module boundary cleanup third** — stop internals leaking across features
4. **Cubit sizing cleanup fourth** — merge artificial micro-cubits and split overloaded cubits only where the state boundary is real
5. **Presentation polish and test backfill last** — rebuild scope, listeners, and missing tests

### Incremental Migration Plan

**Guiding principle:** Each phase is independently deployable.

#### Phase 1 — Registration and Lifecycle Integrity _(~N files, low risk)_

**Goal:** One registration source of truth, intentional provider scope.

- [ ] Move manual dependency graph assembly into `service_locator.dart`
- [ ] Keep `main.dart` as `runApp()` only; resolve app-wide providers from `getIt` in composition roots
- [ ] Convert parameterized route cubits to `registerFactoryParam` or an explicit DI-backed factory
- [ ] Re-scope feature cubits from app-wide to route/screen scope where appropriate

**Safe because:** Mostly wiring and lifecycle work; behavior should stay the same if done carefully.

#### Phase 2 — Break Cubit-to-Cubit Dependencies _(~N files, medium risk)_

**Goal:** No cubit holds another cubit/bloc directly.

For each dependency found:

```text
[SourceCubit] -> [TargetCubit]
Extract: [SharedConcernService]
Register as: singleton / lazySingleton / factory
Replace in: [list of files]
```

**Safe because:** The new domain service can be introduced first, then callers can migrate one by one.

#### Phase 3 — Feature and Module Boundary Cleanup _(~N files, medium risk)_

**Goal:** No feature imports another feature's internals.

For each violation:

```text
[Importing feature] imports [target feature internals]
Replace with: [public contract / dedicated shared module / core infrastructure]
```

Keep `core/` for infrastructure. Shared business logic should usually move to a dedicated shared module/package or a small public API.

#### Phase 4 — Cubit Sizing Cleanup _(~N files, medium risk)_

**Goal:** Cubit boundaries match visible UI state and reasons to change.

For each problem feature:

```text
[feature]
Current cubits: [list]
Issue: artificial split / overloaded cubit
Target shape: [proposed cubits or split]
State to move: [list]
Methods to move: [list]
```

**Do not use a hard max cubit count per feature.** Optimize for coherent state boundaries, not arbitrary numbers.

#### Phase 5 — Presentation Polish and Test Backfill _(ongoing)_

**Goal:** Clean presentation layer and reliable coverage.

- [ ] Narrow `BlocBuilder` scopes to only the widgets that depend on state
- [ ] Replace nested `BlocListener`s with `MultiBlocListener`
- [ ] Use `BlocProvider.value` when reusing an existing cubit across a new subtree
- [ ] Extract widget helper methods only when a separate widget has a clear standalone name and purpose
- [ ] Add repository mapping/failure tests, cubit/bloc state tests, widget tests, and DI smoke tests

### Estimated effort

| Phase | Files affected | Risk | Can be done by LLM agent alone? |
|-------|---------------|------|----------------------------------|
| 1 — Registration/lifecycle | N | Low | ✅ Yes |
| 2 — Cubit decoupling | N | Medium | ✅ Yes, one dependency at a time |
| 3 — Boundaries | N | Medium | ✅ Yes, with review on shared API choices |
| 4 — Cubit sizing | N | Medium | ⚠️ Review each merge/split |
| 5 — Presentation/tests | N | Low | ✅ Yes |

---

## Rules

- **Script first, files second.** Use `fanal` if available.
- **Prefer `rg`.** Use broader scripts before manual spot checks.
- **Be specific.** Every issue names a file and line number.
- **Distinguish severity.** Importing another feature's internals is critical; a missing `listenWhen` is usually a suggestion.
- **Modern exhaustive handling is valid.** `.when()`, `.map()`, and Dart `switch` over sealed states all count.
- **Migration plan always included** when the user has refactoring intent.
- **Phases must be safe.** Never propose a change that breaks compilation mid-phase.
- **Offer to execute.** After the plan, ask: "Which phase would you like me to start with?"
