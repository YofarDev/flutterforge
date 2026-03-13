---
name: flutter-audit
description: Use when the user wants a deep analysis, code review, audit, or incremental refactoring plan for an existing Flutter project. Triggers include: 'review my Flutter project', 'audit my codebase', 'what's wrong with my architecture', 'check my BLoC structure', 'analyze my Flutter app', 'refactoring plan', 'migrate my architecture', or when the user shares Flutter files/folders and asks for feedback. This skill checks compliance against flutter-architecture standards and produces a structured, actionable report with an incremental migration plan.
license: MIT
---

# Flutter Architecture Audit

Structured analysis against `flutter-architecture` standards. Produces a prioritized report
**plus an incremental migration plan** so the codebase can be improved safely, one step at a time.

**Always read `flutter-architecture` skill before auditing.**

---

## Step 1 — Pre-Analysis

Run `fanal` (in current folder) if available. It covers: file tree, feature map, file sizes, cross-feature imports,
anti-patterns, DI wiring integrity, cubit coupling, routing, test coverage.

If unavailable, run these targeted greps manually:

```bash
# Dual wiring — cubits constructed outside service_locator
grep -rn "Cubit(\|Bloc(" lib/ --include="*.dart" \
  | grep -v "_cubit.dart\|_bloc.dart\|_state.dart\|_test.dart\|service_locator"

# Cubit-to-cubit dependencies
grep -rn "final.*Cubit\|final.*Bloc\b" lib/features/**/bloc/ --include="*.dart"

# Cross-feature imports
grep -rn "import.*features/" lib/features/ --include="*.dart" \
  | awk -F: '{print $1, $3}' | grep -v "self"
```

---

## Step 2 — Deep Analysis

### A. BLoC vs Cubit
For each `*_bloc.dart`: is `EventTransformer` (debounce/throttle/switchMap) used?
If not → should be Cubit.

### B. State Exhaustiveness
Are all freezed states handled with `.when()`? Or raw `if (state is X)` checks?

```bash
grep -rn "is _\|state ==" lib/features/*/presentation/ --include="*.dart"
```

### C. Error Handling
Do repositories return `Either<Failure, T>` or throw? Do cubits emit typed failure states?

```bash
grep -A3 "} catch" lib/features/*/presentation/bloc/ --include="*.dart" | grep -v "emit"
```

### D. Presentation Scope
- `BlocBuilder` wrapping full `Scaffold`? (unnecessary rebuilds)
- `BlocConsumer` where `BlocListener` suffices?
- Nested `BlocListener` widgets?

### E. Layer Violations
```bash
grep -rn "import.*data/" lib/features/*/presentation/ --include="*.dart"
```

### F. DI Integrity
- Single `service_locator.dart` / `injection.dart`?
- `app.dart` / `main.dart` using `getIt<>()` only, never constructing cubits manually?
- Singleton vs factory choices consistent?

### G. Cubit Coupling
- Any cubit with `final SomeCubit` or `final SomeBloc` as a field?
- Any feature with >2 cubits that could be consolidated?
- Coordination logic duplicated across cubits instead of extracted to a domain service?

---

## Step 3 — Audit Report

---

### 🏗️ Flutter Architecture Audit — `[project name]`

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

---

#### 🔴 Critical Issues
_Architecture violations that cause cascading breakage. Fix before adding features._

```
[CATEGORY] Title
File: path/to/file.dart (line N)
Problem: What's wrong and why it causes breakage.
Fix: Concrete code or step-by-step instruction.
Migration risk: low / medium / high
```

#### 🟡 Warnings
_Maintenance burden — won't break today but will compound. Same format._

#### 🟢 Suggestions
_Minor improvements. Same format._

---

## Step 4 — Incremental Migration Plan

This section is the primary output when the user asks for a refactoring plan.
The goal is **safe, incremental migration** — each phase must leave the app in a
working state. Never propose a big-bang rewrite.

### Phase sequencing — always this order

1. **DI integrity first** — fix dual wiring before anything else, or every subsequent change risks a hidden second-wiring regression
2. **Cubit decoupling second** — extract domain services to break cubit-to-cubit deps; this unlocks safe consolidation
3. **Cubit consolidation third** — only merge cubits after their deps are clean
4. **Feature boundary cleanup** — remove cross-feature imports, route through `core/`
5. **Presentation polish** — BlocBuilder scope, MultiBlocListener, file sizes

---

### 🗺️ Incremental Migration Plan

**Guiding principle:** Each phase is independently deployable. The app must compile and run after every phase.

---

#### Phase 1 — DI Integrity _(~N files, low risk)_

**Goal:** Single source of truth for all wiring.

- [ ] Move manual cubit constructions from `app.dart`/`main.dart` into `service_locator.dart`
- [ ] Replace every cubit constructed via `context.read` passed as constructor arg with `getIt<>()`
- [ ] Add `// Singletons` / `// Factories` comment sections to `service_locator.dart`

**Safe because:** Pure mechanical move — behavior unchanged, just wiring location.

---

#### Phase 2 — Break Cubit-to-Cubit Dependencies _(~N files, medium risk)_

**Goal:** No cubit holds a reference to another cubit.

For each cubit-to-cubit dependency found:

```
[SourceCubit] → [TargetCubit]
Extract: [SharedConcernService]
Register in service_locator as: lazySingleton
Replace in: [list of files]
```

**Safe because:** New service is additive; old cubits keep working until switched over.
**Do one dependency at a time** — commit after each.

---

#### Phase 3 — Cubit Consolidation _(~N files, medium risk)_

**Goal:** Max 2 cubits per feature. Coordination logic lives in domain services.

For each over-split feature:
```
[feature]: [list of current cubits] → consolidate into [NewCubit, NewMediaCubit]
State to merge: [list]
Methods to move: [list]
```

**Do not start until Phase 2 is complete.**

---

#### Phase 4 — Feature Boundary Cleanup _(~N files, low risk)_

**Goal:** Zero cross-feature imports.

For each violation:
```
[importing feature] imports [target feature]
Move shared code to: core/[module]/
```

---

#### Phase 5 — Presentation Polish _(ongoing)_

**Goal:** Clean presentation layer — no unnecessary rebuilds, no nested listeners.

- [ ] Narrow `BlocBuilder` scopes (wrap only dependent widgets)
- [ ] Replace nested `BlocListener`s with `MultiBlocListener`
- [ ] Extract widget helper methods (`_buildX`) to separate widget classes
- [ ] Identify files with more than one reason to change and extract only where a clear, standalone name exists for the extracted piece

---

### Estimated effort

| Phase | Files affected | Risk | Can be done by LLM agent alone? |
|-------|---------------|------|----------------------------------|
| 1 — DI integrity | N | Low | ✅ Yes |
| 2 — Cubit decoupling | N | Medium | ✅ Yes (one dep at a time) |
| 3 — Consolidation | N | Medium | ⚠️ Review each merge |
| 4 — Feature boundaries | N | Low | ✅ Yes |
| 5 — Presentation | N | Low | ✅ Yes |

---

## Rules

- **Script first, files second.** Use `fanal` if available.
- **Be specific.** Every issue names a file and line number.
- **Distinguish severity.** Cross-feature import → critical. Missing `listenWhen` → suggestion.
- **Migration plan always included** when the user has refactoring intent.
- **Phases must be safe.** Never propose a change that breaks compilation mid-phase.
- **Don't pad.** Compliant category = one line in the summary table.
- **Offer to execute.** After the plan, ask: "Which phase would you like me to start with?"
