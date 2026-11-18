#!/bin/bash
# =============================================================================
# Remove the example counter feature from the project.
#
# Deletes the feature folders and surgically updates every file that
# references them (service_locator, router, home screen, app test).
# Text edits are done in Python — portable across macOS/Linux (no GNU sed
# incompatibilities).
#
# Usage: run from the project root:  ./remove_counter.sh
# =============================================================================
set -e

if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found — run this script from the project root."
    exit 1
fi

echo "🧹 Removing example counter feature..."

# 1. Remove directories
rm -rf lib/features/counter
rm -rf test/features/counter
echo "   ✓ Feature folders deleted"

# 2. Update every referencing file
export PROJECT_ROOT="$(pwd)"
uv run --no-project python - <<'EOF'
import os
import re

root = os.environ['PROJECT_ROOT']

def read(rel):
    with open(os.path.join(root, rel), encoding='utf-8') as f:
        return f.read()

def write(rel, content):
    with open(os.path.join(root, rel), 'w', encoding='utf-8') as f:
        f.write(content)

# Exact demo identifiers only (word-bounded), so user features such as
# `step_counter` / `StepCounter` / `stepCounterRoutes` are never touched.
DEMO_IMPORT = re.compile(r"^\s*(import|export)\s+['\"][^'\"]*features/counter/")
DEMO_TOKEN = re.compile(
    r"\b(?:registerCounterFeature|counterRoutes|counterLocalDataSourceOverride"
    r"|ICounterRepository|ICounterLocalDataSource|CounterCubit|CounterService"
    r"|CounterRepository|CounterLocalDataSource|counterCubit\w*)\b"
)
# Demo-only test files: any identifier or word that *starts* with counter.
BROAD_DEMO = re.compile(
    r"(?<![A-Za-z0-9_])(?:I|Fake|Failing)?[Cc]ounter|fake_counter_data_source"
)

def drop_lines(content, *patterns):
    """Drop every line matched by any pattern (regex objects)."""
    kept = [ln for ln in content.split('\n') if not any(p.search(ln) for p in patterns)]
    return '\n'.join(kept)

def remove_block(content, opener, marker):
    """Remove the balanced-parenthesis block starting at each `opener`
    occurrence whose block contains `marker` (and its trailing comma)."""
    search_from = 0
    while True:
        start = content.find(opener, search_from)
        if start == -1:
            return content
        depth = 0
        i = content.find('(', start)
        j = i
        while j < len(content):
            if content[j] == '(':
                depth += 1
            elif content[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        block = content[start:j + 1]
        if marker in block:
            begin = content.rfind('\n', 0, start) + 1
            end = j + 1
            while end < len(content) and content[end] in ',;':
                end += 1
            if end < len(content) and content[end] == '\n':
                end += 1
            return content[:begin] + content[end:]
        search_from = j + 1

# --- service_locator.dart: counter module import + registration call -----
rel = 'lib/core/di/service_locator.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = remove_block(content, 'registerCounterFeature(', 'Counter')
    # The setupServiceLocator override parameter goes too.
    content = drop_lines(content, DEMO_IMPORT, DEMO_TOKEN)
    write(rel, content)
    print('   ✓ DI registration removed')

# --- route_constants.dart: counter route constant -------------------------
rel = 'lib/core/router/route_constants.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = re.sub(r" *static const String counter = '[^']*';\n", '', content)
    write(rel, content)
    print('   ✓ Route constants updated')

# --- app_router.dart: counter imports + GoRoute block ---------------------
rel = 'lib/core/router/app_router.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = re.sub(r" *\.\.\.counterRoutes\(\w*\),\n", '', content)
    content = drop_lines(content, DEMO_IMPORT, DEMO_TOKEN)
    write(rel, content)
    print('   ✓ Router updated')

# --- home_screen.dart: counter button + description ------------------------
rel = 'lib/features/home/presentation/screens/home_screen.dart'
path = os.path.join(root, rel)
if os.path.exists(path):
    content = read(rel)
    content = remove_block(content, 'FilledButton.icon(', 'tryCounterDemo')
    content = remove_block(content, 'Text(', 'counterDemoDescription')
    content = re.sub(r" *const SizedBox\(height: 32\),\n", '', content)
    content = re.sub(r" *const SizedBox\(height: 8\),\n", '', content)
    # go_router + route_constants become unused once the button is gone
    content = re.sub(r"import 'package:go_router/go_router.dart';\n", '', content)
    content = re.sub(r"import '.*route_constants.dart';\n", '', content)
    write(rel, content)
    print('   ✓ Home screen cleaned up')

# --- app_test.dart: counter mocks/stubs (every line mentioning it) --------
rel = 'test/app_test.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    # The router-rebuild test asserts state retention through the counter's
    # Increment control, so it cannot survive feature removal — drop the
    # whole test case, not just its counter-flavored lines.
    content = re.sub(
        r"\s*testWidgets\(\s*'rebuilding the root widget retains the route "
        r"and state of the '\s*'default-owned router'.*?\}\);\n",
        '\n',
        content,
        flags=re.S,
    )
    content = drop_lines(content, DEMO_IMPORT, BROAD_DEMO)
    write(rel, content)
    print('   ✓ Integration tests cleaned up')

# --- service_locator_test.dart: counter DI smoke expectations --------------
rel = 'test/core/di/service_locator_test.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = drop_lines(content, DEMO_IMPORT, DEMO_TOKEN)
    write(rel, content)
    print('   ✓ DI smoke test cleaned up')

# --- test/support/fake_counter_data_source.dart: pure counter fixture -----
rel = 'test/support/fake_counter_data_source.dart'
if os.path.exists(os.path.join(root, rel)):
    os.remove(os.path.join(root, rel))
    print('   ✓ Counter fake deleted')

# --- home_flow_test.dart: drop counter tests/seams, keep home tests --------
rel = 'test/features/home/home_flow_test.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)

    def remove_all_blocks_re(content, opener, marker):
        """Removes EVERY balanced-parenthesis block opened by `opener` whose
        body contains `marker` (plus its trailing comma)."""
        while True:
            search_from = 0
            removed = False
            while True:
                start = content.find(opener, search_from)
                if start == -1:
                    break
                depth = 0
                i = content.find('(', start)
                j = i
                while j < len(content):
                    if content[j] == '(':
                        depth += 1
                    elif content[j] == ')':
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                block = content[start:j + 1]
                if marker.search(block):
                    begin = content.rfind('\n', 0, start) + 1
                    end = j + 1
                    # Consume the statement/collection terminator (';' or
                    # ',') plus the trailing newline, so no stray ';;'/';'
                    # empty statements are left behind.
                    while end < len(content) and content[end] in ',;':
                        end += 1
                    if end < len(content) and content[end] == '\n':
                        end += 1
                    content = content[:begin] + content[end:]
                    removed = True
                    break
                search_from = j + 1
            if not removed:
                return content

    # Drop every counter-specific testWidgets block as a whole.
    content = remove_all_blocks_re(content, 'testWidgets(', BROAD_DEMO)
    # configureApp loses its counter override parameter...
    content = content.replace(
        'Future<void> configureApp({ICounterLocalDataSource? counterOverride}) async {',
        'Future<void> configureApp() async {',
    )
    # ...then any remaining line mentioning the counter (imports, fields,
    # assignment lines, doc-comment lines).
    content = drop_lines(content, DEMO_IMPORT, BROAD_DEMO)
    write(rel, content)
    print('   ✓ Home flow tests cleaned up')

# --- ARB files: demo localization keys nothing references any more --------
import json

DEMO_KEYS = [
    'counterTitle', 'counterDescription', 'counterIncrement', 'counterDecrement',
    'tryCounterDemo', 'counterDemoDescription', 'reset', 'count',
]
arb_dir = os.path.join(root, 'lib', 'core', 'l10n')
arb_paths = [
    os.path.join(arb_dir, name)
    for name in ('app_localizations_fr.arb', 'app_localizations_en.arb')
    if os.path.isfile(os.path.join(arb_dir, name))
]
if arb_paths:
    corpus = []
    for top in ('lib', 'test'):
        for base, dirs, names in os.walk(os.path.join(root, top)):
            if os.path.abspath(base).startswith(os.path.abspath(arb_dir)):
                continue  # generated AppLocalizations always mentions every key
            for name in names:
                if name.endswith('.dart'):
                    try:
                        with open(os.path.join(base, name), encoding='utf-8') as f:
                            corpus.append(f.read())
                    except OSError:
                        pass
    text = '\n'.join(corpus)
    removable = [k for k in DEMO_KEYS if not re.search(r'\b' + re.escape(k) + r'\b', text)]
    changed = []
    for path in arb_paths:
        try:
            with open(path, encoding='utf-8') as f:
                data = json.load(f)
        except (OSError, ValueError):
            print(f'   ⚠️  {os.path.basename(path)} is not valid JSON — demo keys left in place')
            continue
        if not isinstance(data, dict):
            continue
        gone = [k for k in removable if k in data or '@' + k in data]
        if not gone:
            continue
        for k in gone:
            data.pop(k, None)
            data.pop('@' + k, None)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.write('\n')
        changed.append(path)
    if changed:
        open(os.path.join(root, '.forge_arb_changed'), 'w').close()
        print('   ✓ Unused demo l10n keys removed: ' + ', '.join(removable))
EOF

# 3. Re-format the files edited above (surgical text edits are not
#    formatter-exact; fverify's format gate is a CHECK, so the files this
#    script touches are brought into compliance here).
if command -v dart >/dev/null 2>&1; then
    dart format \
        lib/core/di/service_locator.dart \
        lib/core/router/route_constants.dart \
        lib/core/router/app_router.dart \
        lib/features/home/presentation/screens/home_screen.dart \
        test/app_test.dart \
        test/core/di/service_locator_test.dart \
        test/features/home/home_flow_test.dart >/dev/null \
        || echo "   ⚠️  dart format reported an issue — fverify will surface it."
    echo "   ✓ Edited files re-formatted"
else
    echo "   ⚠️  'dart' not found — run 'dart format .' before fverify."
fi

# 4. Regenerate localizations when ARB keys were removed.
if [ -f .forge_arb_changed ]; then
    rm -f .forge_arb_changed
    if [ "${FORGE_SKIP_GEN_L10N:-0}" = "1" ]; then
        : # set by the upgrade helper for its reference trees (not a Flutter app)
    elif command -v flutter >/dev/null 2>&1; then
        if flutter gen-l10n >/dev/null; then
            echo "   ✓ Localizations regenerated"
        else
            echo "❌ 'flutter gen-l10n' failed — fix the ARB files, then run it again."
            exit 1
        fi
    else
        echo "   ⚠️  'flutter' not found — run 'flutter gen-l10n' before fverify."
    fi
fi

echo "✅ Counter feature removal complete!"
echo "   Run ./scripts/fverify.sh (or fverify) to confirm everything still passes."
