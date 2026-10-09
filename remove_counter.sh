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
uv run python - <<'EOF'
import os
import re

root = os.environ['PROJECT_ROOT']

def read(rel):
    with open(os.path.join(root, rel), encoding='utf-8') as f:
        return f.read()

def write(rel, content):
    with open(os.path.join(root, rel), 'w', encoding='utf-8') as f:
        f.write(content)

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
            if end < len(content) and content[end] == ',':
                end += 1
            if end < len(content) and content[end] == '\n':
                end += 1
            return content[:begin] + content[end:]
        search_from = j + 1

# --- service_locator.dart: counter imports + registrations ---------------
rel = 'lib/core/di/service_locator.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = re.sub(r"import .*counter[^\n]*\n", '', content, flags=re.I)
    content = re.sub(
        r"\n *getIt\.register\w*<?I?Counter\w*>?\(\n(?:.*\n)*? *\);",
        '\n',
        content,
    )
    # The setupServiceLocator override parameter and its fallback line go too.
    content = ''.join(
        line + '\n' for line in content.split('\n')[:-1] if 'ounter' not in line
    )
    write(rel, content)
    print('   ✓ DI registrations removed')

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
    content = re.sub(r"import .*counter[^\n]*\n", '', content, flags=re.I)
    content = remove_block(content, 'GoRoute(', 'Routes.counter')
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
    content = ''.join(
        line + '\n' for line in content.split('\n')[:-1] if 'ounter' not in line
    )
    write(rel, content)
    print('   ✓ Integration tests cleaned up')

# --- service_locator_test.dart: counter DI smoke expectations --------------
rel = 'test/core/di/service_locator_test.dart'
if os.path.exists(os.path.join(root, rel)):
    content = read(rel)
    content = ''.join(
        line + '\n' for line in content.split('\n')[:-1] if 'ounter' not in line
    )
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

    def remove_all_blocks(content, opener, marker):
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
                if marker in block:
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
    content = remove_all_blocks(content, 'testWidgets(', 'ounter')
    # configureApp loses its counter override parameter...
    content = content.replace(
        'Future<void> configureApp({ICounterLocalDataSource? counterOverride}) async {',
        'Future<void> configureApp() async {',
    )
    # ...then any remaining line mentioning the counter (imports, fields,
    # assignment lines, doc-comment lines).
    content = ''.join(
        line + '\n' for line in content.split('\n')[:-1] if 'ounter' not in line
    )
    write(rel, content)
    print('   ✓ Home flow tests cleaned up')
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

echo "✅ Counter feature removal complete!"
echo "   Run ./scripts/fverify.sh (or fverify) to confirm everything still passes."
