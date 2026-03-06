# RED Phase Test Scenarios: flutter-testing

## Purpose
Document baseline behavior WITHOUT the skill to prove it addresses real problems.

## Pressure Scenario 1: Academic Understanding
**Question:** "What's the standard approach for testing a Cubit in Flutter? What tools should I use?"

**Expected baseline failures (without skill):**
- May not mention `bloc_test` package
- May not test all state transitions (loading, success, failure)
- May not test error paths
- May not know to use `mocktail` for dependencies

## Pressure Scenario 2: Application - Write Cubit Tests
**Task:** "Write tests for this AuthCubit with a login method"

**Expected baseline failures:**
- May test implementation details (private methods)
- May not use `blocTest` wrapper
- May not mock dependencies properly
- May not test error states
- May not verify state sequence

## Pressure Scenario 3: Time Pressure + Complexity
**Task:** "We need test coverage for this feature quickly. Write tests for the repository, cubit, and screen."

**Expected baseline failures:**
- May skip error paths ("just happy path for now")
- May test layers in wrong order
- May use wrong mock setup
- May not know folder structure should mirror lib/

## Pressure Scenario 4: Widget Test Specifics
**Question:** "How do I test a widget that uses a Bloc? Should I use the real cubit?"

**Expected baseline failures:**
- May try to instantiate real cubit (bad practice)
- May not know to use `BlocProvider.value`
- May not use `fake` or `mock` cubits
- May not know `pump()` vs `pumpAndSettle()`

## Pressure Scenario 5: Multiple Pressures Combined
**Context:** User is frustrated with flaky tests, under deadline, asks "Why are my tests failing randomly? These widget tests are a nightmare."

**Expected baseline failures:**
- May not diagnose async timing issues
- May not recommend `pump(duration)` instead of `pumpAndSettle()`
- May not identify over-specified tests
- May not suggest golden tests for visual regression

## Success Criteria (WITH skill)
Agent should:
1. Recommend `bloc_test` for cubits, `mocktail` for mocks
2. Test all state transitions including error paths
3. Use proper mock setup with `when(() => ...)`
4. Mirror lib/ structure in test/ folder
5. Use `BlocProvider.value` or fake cubits for widget tests
6. Diagnose timing issues and recommend proper async handling
