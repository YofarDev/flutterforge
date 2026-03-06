#!/bin/bash

# Check if pubspec.yaml exists in current directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found in current directory"
    echo "Please run this script from a Flutter project root directory"
    exit 1
fi

# Check if lib/ directory exists
if [ ! -d "lib" ]; then
    echo "❌ Error: lib/ directory not found"
    echo "Please run this script from a Flutter project root directory"
    exit 1
fi

# If argument provided, check specific package
if [ ! -z "$1" ]; then
    PACKAGE_NAME="$1"
    echo "🔍 Checking if '$PACKAGE_NAME' is used in lib/..."
    echo ""
    
    if grep -r "import 'package:$PACKAGE_NAME" lib/ > /dev/null 2>&1; then
        echo "✅ Package '$PACKAGE_NAME' IS used"
        echo ""
        echo "Found in:"
        grep -rn "import 'package:$PACKAGE_NAME" lib/ | sed 's/:/ - line /'
    else
        echo "❌ Package '$PACKAGE_NAME' is NOT used"
        echo ""
        echo "You can safely remove it from pubspec.yaml"
    fi
    exit 0
fi

# If no argument, check all dependencies
echo "=== Checking for unused dependencies ==="
echo ""

# Get ONLY regular dependencies from pubspec.yaml using awk.
# This strictly extracts the `dependencies:` block and inherently ignores `dev_dependencies`
DECLARED=$(awk '
    /^dependencies:/ { in_deps=1; next }
    /^[a-zA-Z_-]+:/ { in_deps=0 }
    in_deps && /^  [a-zA-Z0-9_-]+:/ { print $1 }
' pubspec.yaml | tr -d ':' | grep -vE "^(flutter|cupertino_icons)$")

# Get actually imported packages from lib/
IMPORTED=$(grep -rh "import 'package:" lib/ 2>/dev/null | grep -o "package:[^/]*" | sed 's/package://g' | sort -u)

UNUSED_COUNT=0
USED_COUNT=0

echo "📦 Potentially unused dependencies:"
echo ""
for dep in $DECLARED; do
    if ! echo "$IMPORTED" | grep -q "^$dep$"; then
        echo "  ❌ $dep"
        ((UNUSED_COUNT++))
    else
        ((USED_COUNT++))
    fi
done

if [ $UNUSED_COUNT -eq 0 ]; then
    echo "  (none - all dependencies are being used!)"
fi

echo ""
echo "📊 Summary:"
echo "  Used: $USED_COUNT"
echo "  Unused: $UNUSED_COUNT"
echo ""
echo "💡 Tip: Run with package name to see where it's used:"
echo "   $(basename "$0") package_name"