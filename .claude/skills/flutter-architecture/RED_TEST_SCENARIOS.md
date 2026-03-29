# RED Phase Test Scenarios: flutter-architecture

## Purpose
Document baseline behavior WITHOUT the skill to prove it addresses real problems.

## Pressure Scenario 1: Academic Understanding
**Question:** "What's the best way to structure a new Flutter feature? Should I use BLoC or Cubit?"

**Expected baseline failures (without skill):**
- May not recommend layered architecture (data/domain/presentation)
- May not distinguish when to use Cubit vs BLoC
- May suggest BLoC for everything (over-engineering)
- May not mention `freezed` for states
- May not mention dependency injection patterns

## Pressure Scenario 2: Create New Feature
**Task:** "Create a chat feature with message list and send button"

**Expected baseline failures:**
- May put everything in one folder/file
- May inject dependencies directly in widgets
- May use mutable state classes
- May not separate repository interface from implementation
- May import directly from other features (violating boundaries)
- May not use `freezed` for states

## Pressure Scenario 3: Refactor Existing Code
**Task:** "This screen file is 800 lines. How should I restructure it?"

**Expected baseline failures:**
- May not suggest extracting to widgets/ subdirectory
- May not identify business logic that belongs in Cubit
- May not recommend separating data/domain/presentation
- May not suggest extracting repositories
- May not identify cross-feature imports

## Pressure Scenario 4: Multiple Listeners Problem
**Task:** "I have 3 BlocListeners nested and it's hard to read. Any suggestions?"

**Expected baseline failures (without skill):**
- May not recommend `MultiBlocListener`
- May suggest flattening but not provide pattern
- May not show listener extraction to methods
- May not mention `listenWhen` optimization

## Pressure Scenario 5: Navigation Side Effects
**Context:** User reports "Navigate is called in build() and I get Flutter errors"

**Expected baseline failures:**
- May not identify this as anti-pattern
- May not recommend `BlocListener` for navigation
- May not show proper `state.whenOrNull()` pattern
- May not warn about `context.read` after `await`

## Pressure Scenario 6: Time Pressure + Sunk Cost
**Task:** "We need to add this auth check across 5 screens. We're already late, just add it directly to each screen's build method."

**Expected baseline failures:**
- May agree to expedient approach (violating architecture)
- May not recommend centralized auth check via `redirect` in router
- May not warn about maintenance burden
- May not suggest `BlocListener` pattern

## Success Criteria (WITH skill)
Agent should:
1. Recommend layered architecture with clear boundaries
2. Use Cubit by default, and recommend BLoC when explicit events or concurrency policies improve clarity
3. Prefer `freezed` for states/models, while accepting plain sealed immutable states when handled exhaustively
4. Recommend `MultiBlocListener` for multiple listeners
5. Never put navigation in build()
6. Extract business logic from widgets to Cubits
7. Split files by cohesion and reasons to change, not arbitrary line-count limits
8. Use dependency injection, never instantiate in widgets
