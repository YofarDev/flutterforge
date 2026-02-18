#!/bin/bash
# Script to create a new Flutter project with custom template
# Usage: ./create_flutter_project.sh [--org=<organization>] [flutter_create_args] <project_name>
# Example: ./create_flutter_project.sh --org=com.mycompany --platforms=android,ios my_new_app
#          ./create_flutter_project.sh my_new_app
set -e

# Default organization
ORG="fr.yofardev"

# Get the absolute path of the script directory (template source)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
PROJECT_NAME=""
FLUTTER_ARGS=()

for arg in "$@"; do
    if [[ "$arg" == --org=* ]]; then
        # Extract custom organization
        ORG="${arg#--org=}"
    elif [[ "$arg" != -* ]]; then
        # This is the project name (last non-option argument)
        PROJECT_NAME="$arg"
        FLUTTER_ARGS+=("$arg")
    else
        # Other flutter create arguments
        FLUTTER_ARGS+=("$arg")
    fi
done

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 [--org=<organization>] [options] <project_name>"
    echo "Example: $0 --org=com.mycompany --platforms=android,ios my_app"
    echo "Example: $0 my_app"
    exit 1
fi

echo "🚀 Creating Flutter project '$PROJECT_NAME'..."
echo "   Organization: $ORG"

# 1. Create the project
# We pass "--org" first, then all user arguments.
flutter create --org "$ORG" "${FLUTTER_ARGS[@]}"

cd "$PROJECT_NAME"

# 2. Copy lib folder template
echo "📂 Copying 'lib' folder from template..."
rm -rf lib
cp -r "$SCRIPT_DIR/lib" .

# 3. Copy test folder template
echo "🧪 Copying 'test' folder from template..."
rm -rf test
cp -r "$SCRIPT_DIR/test" .

# 4. Update import paths in test files
echo "🔧 Updating import paths in test files..."
# Replace the placeholder package name with the actual project name
find test -name "*.dart" -type f -exec sed -i.bak "s/package:my_flutter_app/package:$PROJECT_NAME/g" {} \;
# Remove backup files
find test -name "*.bak" -type f -delete
echo "   ✓ Import paths updated"

# 5. Copy .claude folder (contains skills and configuration)
echo "🤖 Copying '.claude' folder..."
if [ -d "$SCRIPT_DIR/.claude" ]; then
    cp -r "$SCRIPT_DIR/.claude" .
    echo "   ✓ .claude folder copied"
else
    echo "⚠️  Warning: .claude folder not found in template. Skipping."
fi

# 6. Copy analysis_options.yaml
echo "⚙️  Copying 'analysis_options.yaml'..."
cp "$SCRIPT_DIR/analysis_options.yaml" .

# 7. Copy l10n.yaml configuration
echo "🌐 Copying 'l10n.yaml'..."
if [ -f "$SCRIPT_DIR/l10n.yaml" ]; then
    cp "$SCRIPT_DIR/l10n.yaml" .
    echo "   ✓ l10n.yaml copied"
else
    echo "⚠️  Warning: l10n.yaml not found in template. Skipping."
fi

# 8. Copy .gitignore template
echo "📋 Copying '.gitignore'..."
if [ -f "$SCRIPT_DIR/template-gitignore" ]; then
    # Flutter create generates a .gitignore, so we append to it
    cat "$SCRIPT_DIR/template-gitignore" >> .gitignore
    echo "   ✓ .gitignore updated"
else
    echo "⚠️  Warning: template-gitignore not found in template. Skipping."
fi

# 9. Copy Inter font files
echo "🔤 Setting up Inter font..."
FONT_SOURCE="$SCRIPT_DIR/fonts"
if [ -d "$FONT_SOURCE" ]; then
    mkdir -p assets/fonts/
    cp -r "$FONT_SOURCE"/* assets/fonts/
    echo "   ✓ Font files copied to assets/fonts/"
else
    echo "⚠️  Warning: Font folder '$FONT_SOURCE' not found. Skipping fonts."
fi

# 10. Remove comments from pubspec.yaml
# This removes lines starting with # (ignoring leading whitespace)
echo "🧹 Removing comments from pubspec.yaml..."
sed -E '/^[[:space:]]*#/d' pubspec.yaml > pubspec.tmp && mv pubspec.tmp pubspec.yaml

# 11. Add assets and font configuration to pubspec.yaml
echo "📝 Adding assets and font configuration to pubspec.yaml..."

# Check if flutter section exists and add assets/fonts configuration
if grep -q "^flutter:" pubspec.yaml; then
    # Check if assets section already exists
    if ! grep -q "^[[:space:]]*assets:" pubspec.yaml; then
        # Find the line number of "flutter:" and add assets after it
        awk '/^flutter:/ {print; print "  assets:\n    - assets/"; next} 1' pubspec.yaml > pubspec.tmp && mv pubspec.tmp pubspec.yaml
        echo "   ✓ Assets configuration added"
    else
        echo "   ⚠️  Assets section already exists, skipping"
    fi
    
    # Add fonts configuration if font files exist
    if [ -d "assets/fonts" ] && [ "$(ls -A assets/fonts 2>/dev/null)" ]; then
        if ! grep -q "^[[:space:]]*fonts:" pubspec.yaml; then
            cat >> pubspec.yaml << 'EOF'

  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter/Inter-Regular.ttf
        - asset: assets/fonts/Inter/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter/Inter-Bold.ttf
          weight: 700
EOF
            echo "   ✓ Font configuration added"
        else
            echo "   ⚠️  Fonts section already exists, skipping"
        fi
    fi
else
    echo "   ⚠️  Flutter section not found in pubspec.yaml"
fi

# 12. Add localization packages
echo "🌐 Adding localization packages..."
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl:any

# 13. Add packages from packages_to_add.json
PACKAGES_FILE="$SCRIPT_DIR/packages_to_add.json"
if [ -f "$PACKAGES_FILE" ]; then
    echo "📦 Adding packages from packages_to_add.json..."

    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: 'jq' is not installed. Cannot parse packages_to_add.json."
        exit 1
    fi
    # Add regular dependencies
    DEPS=$(jq -r '.dependencies[] // empty' "$PACKAGES_FILE")
    for pkg in $DEPS; do
        echo "   + Adding dependency: $pkg"
        flutter pub add "$pkg"
    done
    # Add dev dependencies
    DEV_DEPS=$(jq -r '.dev_dependencies[] // empty' "$PACKAGES_FILE")
    for pkg in $DEV_DEPS; do
        echo "   + Adding dev_dependency: $pkg"
        flutter pub add --dev "$pkg"
    done
else
    echo "⚠️  Warning: '$PACKAGES_FILE' not found. Skipping packages."
fi

# 14. Enable generation in pubspec.yaml
echo "⚙️  Enabling generation in pubspec.yaml..."
if grep -q "^flutter:" pubspec.yaml; then
    if ! grep -q "^[[:space:]]*generate:" pubspec.yaml; then
        # Add generate: true after flutter:
        awk '/^flutter:/ {print; print "  generate: true"; next} 1' pubspec.yaml > pubspec.tmp && mv pubspec.tmp pubspec.yaml
        echo "   ✓ Generation enabled"
    else
        echo "   ⚠️  Generate already configured, skipping"
    fi
fi

# 15. Generate localization files
echo "🌐 Generating localization files..."
flutter gen-l10n
echo "   ✓ Localization files generated"

# 16. Run build_runner (for freezed code generation)
echo "🔧 Running build_runner for code generation..."
echo "   (This may take a minute...)"
dart run build_runner build --delete-conflicting-outputs
echo "   ✓ Code generation complete"

# 17. Copy README.md
echo "📄 Copying README.md..."
if [ -f "$SCRIPT_DIR/README.md" ]; then
    cp "$SCRIPT_DIR/README.md" .
    echo "   ✓ README.md copied"
else
    echo "⚠️  Warning: README.md not found in template. Skipping."
fi

echo "✅ Project setup complete!"

# 18. Open in VS Code
echo "📝 Opening project in VS Code..."
code .