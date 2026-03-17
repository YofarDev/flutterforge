# RED Phase Test Scenarios: flutter-bloc-provider

## Purpose
Document baseline behavior WITHOUT the skill to prove it addresses real problems.

## Pressure Scenario 1: The Classic Provider Error
**Context:** User shows error: "Could not find the correct Provider<HomeCubit> above this Widget"

**Expected baseline failures (without skill):**
- May not diagnose root cause (provider below consumer)
- May suggest adding BlocProvider inside the screen itself (wrong)
- May not show `builder:` callback pattern
- May not recommend providing at route level

## Pressure Scenario 2: Scaffold New Screen with Cubit
**Task:** "Create a profile screen that uses a ProfileCubit"

**Expected baseline failures:**
- May wrap BlocProvider inside the screen's build method (same context error)
- May not provide cubit at route level
- May not distinguish between providing and consuming
- May create provider below where it's consumed

## Pressure Scenario 3: Multiple Screens, Same Cubit
**Task:** "I have HomeScreen and SettingsScreen both using ThemeCubit. How do I set this up?"

**Expected baseline failures:**
- May provide cubit in each route (duplication)
- May not recommend providing at app level in main.dart
- May not distinguish between app-wide and route-scoped cubits
- May create state synchronization issues

## Pressure Scenario 4: Async Gap Error
**Task:** User reports "My app crashes when I call context.read after an await"

**Expected baseline failures:**
- May not diagnose widget disposal issue
- May not show capturing cubit before await pattern
- May suggest using global variable (anti-pattern)
- May not explain the root cause clearly

## Pressure Scenario 5: Time Pressure
**Context:** "This provider error is blocking us. Just wrap everything in a BlocProvider at the top of main.dart."

**Expected baseline failures:**
- May agree to expedient but wrong fix
- May not warn about unnecessary rebuilds
- May not distinguish between app-wide and route-scoped needs
- May create performance issues with over-provision

## Pressure Scenario 6: Navigation Cross-Route
**Task:** "Screen A provides ChatCubit. I navigate to Screen B and try to read it, but it throws."

**Expected baseline failures:**
- May not explain provider scoping to subtree
- May suggest making cubit global (over-engineering)
- May not show re-providing pattern
- May not distinguish between shared and isolated state

## Success Criteria (WITH skill)
Agent should:
1. Always provide BlocProvider ABOVE the consuming widget
2. Use route-level provider for route-scoped cubits
3. Use app-level MultiBlocProvider for global cubits
4. Show `builder:` callback pattern when providing in build()
5. Capture context.read before await in async methods
6. Never put BlocProvider inside screen it provides (unless using builder:)
7. Explain provider scoping clearly
8. Distinguish app-wide vs route-scoped vs shared state needs
