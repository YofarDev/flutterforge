---
name: flutter-widget-refactor
description: Use when the user wants to improve widget structure, screen readability, or presentation-layer organization in an existing Flutter codebase — WITHOUT changing behavior or touching state/data layers. Triggers include: "refactor my widgets", "clean up my screen", "split this widget", "my build method is too big", "organize my UI code", "extract widgets", "improve readability", "widget structure", "presentation layer cleanup". Do NOT use for BLoC/Cubit changes, routing, DI, or repository work — use flutter-architecture or flutter-audit for those. If the user shares a screen or widget file and asks for feedback or improvement, use this skill.
license: MIT
---

# Flutter Widget Refactor

Focused presentation-layer surgery: improve widget structure, screen readability, and
folder organization — **without changing behavior or touching layers below `presentation/`**.

**Always check flutter-architecture anti-patterns before proposing any extraction.**

---

## Scope — What This Skill Covers

| ✅ In scope | ❌ Out of scope |
|------------|----------------|
| Extracting `_buildX()` helper methods to proper widget classes | Cubit/BLoC logic changes |
| Narrowing `BlocBuilder` / `BlocConsumer` scope | Repository or domain layer changes |
| Replacing nested `BlocListener`s with `MultiBlocListener` | DI wiring (`service_locator.dart`) |
| Moving screen-specific widgets to `widgets/` subdirectory | Routing changes |
| Identifying over-fragmented micro-widgets to merge | State model changes |
| Fixing rebuild scope (`const`, widget boundaries) | Cross-feature boundary decisions |
| Renaming widgets to reflect their actual purpose | Any behavior change |

If the user's problem involves BLoC structure, DI, or layer violations → use **flutter-audit** instead.

---

## Step 1 — Read the Files

Before analyzing, collect:
- The screen file(s) the user shared
- Any existing `widgets/` subdirectory for that feature
- Any widget referenced but not shared (note it as unknown)

Do **not** invent widget contents that weren't shared. If a referenced widget is unknown, flag it as out-of-scope.

---

## Step 2 — Analyze Each Build Method

For every `build()` method and every `_buildX()` helper, apply this checklist:

**Rebuild scope**
- Is a `BlocBuilder` or `BlocConsumer` wrapping a `Scaffold` or large subtree that contains static children?
- Are there `const` widgets that could be hoisted but aren't?

**Helper method smell**
- Does a `_buildX()` helper have a clear, standalone name and purpose?
- Would it benefit from its own `const` constructor?
- Is it used in more than one place?

**Over-fragmentation smell**
- Are there widgets so small (< ~10 lines, no local state, no semantic meaning) that they add noise rather than clarity?
- Do two small widgets always appear together and could be one?

**Ownership**
- Is a widget defined inside a screen file but clearly reusable across features?
- Is a widget defined in `core/` but actually screen-specific?

---

## Step 3 — Decision Table

For each identified piece, assign one of five actions:

| Action | When to use |
|--------|-------------|
| **Keep** | Already correct — extracting would add no clarity |
| **Extract** | Has a clear standalone name, independent rebuild scope, or local state |
| **Merge** | Two or more micro-widgets always appear together, no independent lifecycle |
| **Move** | Right abstraction, wrong location (screen → `widgets/`, `widgets/` → `core/`) |
| **Rename** | Name doesn't reflect what it actually renders |

**The bar for Extract:** Can you give it a clear, specific name? Does it have a reason to change independently from the screen? If both answers aren't yes — Keep.

**The bar for Merge:** Do the two pieces share all their state? Do they always appear together? If yes — Merge.

---

## Step 4 — Report

Produce findings in this format:

---

### 🧩 Widget Refactor — `[ScreenName / file path]`

#### Summary

| Category | Status | Issues |
|----------|--------|--------|
| BlocBuilder scope | ✅/⚠️/❌ | n |
| Helper method extraction | ✅/⚠️/❌ | n |
| Over-fragmentation | ✅/⚠️/❌ | n |
| Rebuild optimization | ✅/⚠️/❌ | n |
| Widget location / ownership | ✅/⚠️/❌ | n |
| Naming | ✅/⚠️/❌ | n |

---

#### 🔴 Critical
_Causes unnecessary rebuilds or makes the screen actively hard to modify._

```
[ACTION] WidgetOrMethodName
File: path/to/file.dart (line N)
Problem: What's wrong and why it hurts maintainability.
Decision: Extract / Merge / Move / Rename / Keep — because [reason].
```
Then provide the refactored code immediately below.

#### 🟡 Warnings
_Adds noise or slows down future edits. Same format._

#### 🟢 Suggestions
_Minor clarity improvements. Same format._

---

## Step 5 — Refactored Code

After the report, output **complete refactored files** — not diffs, not snippets.

Rules for output:
- One code block per file
- Each file labeled with its target path
- `const` constructors on every stateless widget that qualifies
- `super.key` on every widget constructor
- Screen-specific widgets go in `features/[feature]/presentation/widgets/`
- Genuinely reusable widgets go in `core/widgets/` — only if reuse is certain, not speculative
- Never output a widget file with a single widget that is < 15 lines unless it has local state

---

## Extraction Rules — Quick Reference

```
// ❌ DON'T extract — no standalone identity
Widget _buildDivider() => const Divider(height: 1);

// ✅ DO extract — clear name, independent rebuild scope
Widget _buildMessageBubble(Message msg) { ... }
// → class MessageBubble extends StatelessWidget

// ❌ DON'T extract — only reason is line count
// ChatScreen.build() is 300 lines but is one coherent composition
// → splitting creates micro-widgets that must be passed the same state

// ✅ DO extract — different reason to change
// Header section changes when branding changes
// Message list changes when data model changes
// → class ChatHeader, class MessageList
```

---

## BlocBuilder Scope Rules — Quick Reference

```dart
// ❌ DON'T — entire Scaffold rebuilds on every state change
BlocBuilder<ChatCubit, ChatState>(
  builder: (context, state) => Scaffold(
    appBar: AppBar(title: Text(state.title)), // drives the rebuild
    body: Column(children: [
      const HeavyStaticWidget(), // rebuilds for free — wasteful
      MessageList(messages: state.messages),
    ]),
  ),
)

// ✅ DO — wrap only what depends on state
Scaffold(
  appBar: AppBar(
    title: BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (prev, curr) => prev.title != curr.title,
      builder: (_, state) => Text(state.title),
    ),
  ),
  body: Column(children: [
    const HeavyStaticWidget(),
    BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (prev, curr) => prev.messages != curr.messages,
      builder: (_, state) => MessageList(messages: state.messages),
    ),
  ]),
)
```

---

## Helper Method Rules — Quick Reference

```dart
// ❌ WRONG — rebuilds whenever parent rebuilds, can't be const
class ChatScreen extends StatelessWidget {
  Widget _buildEmptyState() => const Center(child: Text('No messages'));

  @override
  Widget build(BuildContext context) {
    return _buildEmptyState(); // same-instance call, no optimization possible
  }
}

// ✅ CORRECT — Flutter's element tree can short-circuit with const
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatEmptyState(); // const → skip rebuild if unchanged
  }
}

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('No messages'));
}
```

---

## Over-Fragmentation Rules — Quick Reference

```
// ❌ TOO GRANULAR — these always appear together, share all state
class MessageAvatar extends StatelessWidget { ... }    // 8 lines
class MessageSenderName extends StatelessWidget { ... } // 6 lines
class MessageTimestamp extends StatelessWidget { ... }  // 5 lines
// → three files, zero independent reuse, caller must coordinate three widgets

// ✅ BETTER — one coherent unit
class MessageHeader extends StatelessWidget {
  // avatar + sender name + timestamp, composed here
}
```

---

## Output Checklist — Before Finishing

- [ ] Every extracted widget has `const` constructor if stateless
- [ ] Every widget has `super.key`
- [ ] `BlocBuilder`s use `buildWhen` where the state has multiple fields
- [ ] No widget file contains only a trivial wrapper (< 15 lines, no local state)
- [ ] Screen file clearly reads as a composition — no business logic, no data fetching
- [ ] Folder structure matches: screen-specific → `widgets/`, shared → `core/widgets/`
- [ ] Complete files provided, not snippets
- [ ] Behavior is identical to before

---

## Interaction with Other Skills

| If you also need... | Use skill |
|--------------------|-----------|
| Full holistic audit (DI, cubit coupling, layer violations) | `flutter-audit` |
| New feature scaffolding or architecture decisions | `flutter-architecture` |
| Widget refactor only, behavior unchanged | **this skill** |

When flutter-audit Phase 5 ("Presentation Polish") surfaces widget issues,
hand off to this skill for the actual implementation.

---

## See Also
- `flutter-architecture` → Anti-Patterns table (widget helper methods, BlocBuilder scope)
- `flutter-audit` → Step 2D (Presentation Scope) and Phase 5 (Presentation Polish)
