---
name: flutter-audit
description: Use when the user wants a deep analysis, code review, or audit of an existing Flutter project. Triggers include: 'review my Flutter project', 'audit my codebase', 'what's wrong with my architecture', 'check my BLoC structure', 'analyze my Flutter app', or when the user shares Flutter files/folders and asks for feedback. This skill checks compliance against the flutter-architecture standards and produces a structured, actionable report.
license: MIT
---

# Flutter Architecture Audit

Structured analysis against `flutter-architecture` standards. Produces prioritized, actionable report.

**Read `flutter-architecture` before auditing.**

## Step 1 — Pre-Analysis (Optional)

If `fanal` script exists:
```bash
fanal
```

Covers: feature map, file sizes, cross-feature imports, anti-patterns, state design, DI stats, test coverage.

**If unavailable**, proceed to Step 2.

## Step 2 — Deep Analysis

### A. BLoC vs Cubit
For each `*_bloc.dart`:
- Is `EventTransformer` (debounce/throttle/switchMap) used?
- If not → should be Cubit

### B. State Exhaustiveness
For `@freezed` states:
- All states handled with `.when()`/`.maybeWhen()`?
- Or raw `if (state is X)` checks?

```bash
grep -rn "is _\|state ==" lib/features/*/presentation/ --include="*.dart"
```

### C. Error Handling
- Repositories return `Either<Failure, T>` or throw?
- Cubits emit typed failure states or swallow silently?

```bash
grep -A3 "} catch" lib/features/*/presentation/bloc/ --include="*.dart" | grep -v "emit"
```

### D. Presentation Scope
- `BlocBuilder` wrapping full `Scaffold`? (unnecessary rebuilds)
- `BlocConsumer` where `BlocListener` suffices?
- Nested `BlocListener` widgets? (use `MultiBlocListener`)

### E. Layer Violations
```bash
grep -rn "import.*data/" lib/features/*/presentation/ --include="*.dart"
```

### F. Dependencies
- `flutter_bloc`, `get_it`, `go_router`, `freezed` present?
- No `http` where API abstraction needed?
- No conflicting state packages (provider, riverpod)?

## Step 3 — Report Format

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
| DI | ✅/⚠️/❌ | n |
| Routing | ✅/⚠️/❌ | n |
| Models | ✅/⚠️/❌ | n |
| Standards | ✅/⚠️/❌ | n |

---

#### 🔴 Critical Issues
_Architecture violations or bugs. Fix first._

```
[CATEGORY] Title
File: path/to/file.dart (line N)
Problem: What's wrong and why.
Fix: Concrete code or instruction.
```

#### 🟡 Warnings
_Maintenance burden. Same format._

#### 🟢 Suggestions
_Minor improvements. Same format._

---

#### Recommended Fix Order
_Numbered, most impactful first._

---

## Rules

- **Script first, files second.** Use `fanal` if available.
- **Be specific.** Every issue must name a file.
- **Distinguish severity.** Cross-feature import → critical. Missing `listenWhen` → suggestion.
- **Don't pad.** Compliant category = one line.
- **Offer to fix.** Ask: "Would you like me to fix any of these?"
