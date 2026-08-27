#!/usr/bin/env bash

# Add localized strings to Flutter .arb files and regenerate localization files
# Usage: add-l10n-string <keyName> <frString> <enString> [projectPath]

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 3 ]; then
    echo "Usage: add-l10n-string <keyName> <frString> <enString> [projectPath]"
    echo ""
    echo "Arguments:"
    echo "  keyName     - The localization key (camelCase, e.g., dashboardWelcome)"
    echo "  frString    - French translation (source of truth)"
    echo "  enString    - English translation"
    echo "  projectPath - Optional path to Flutter project (defaults to current directory)"
    echo ""
    echo "Example:"
    echo "  add-l10n-string myNewKey \"Bonjour\" \"Hello\""
    echo "  add-l10n-string myNewKey \"Bonjour\" \"Hello\" /path/to/project"
    exit 1
fi

KEY_NAME="$1"
FR_STRING="$2"
EN_STRING="$3"
PROJECT_PATH="${4:-.}"

# Resolve to absolute path
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd) || {
    echo -e "${RED}Error: Project path '$PROJECT_PATH' does not exist${NC}"
    exit 1
}

L10N_DIR="$PROJECT_PATH/lib/core/l10n"
FR_FILE="$L10N_DIR/app_localizations_fr.arb"
EN_FILE="$L10N_DIR/app_localizations_en.arb"

# Check if files exist
if [ ! -f "$FR_FILE" ]; then
    echo -e "${RED}Error: French ARB file not found at $FR_FILE${NC}"
    exit 1
fi

if [ ! -f "$EN_FILE" ]; then
    echo -e "${RED}Error: English ARB file not found at $EN_FILE${NC}"
    exit 1
fi

# Function to safely add an entry to an ARB file
add_to_arb() {
    # Exporting as environment variables makes it 100% safe to pass to Python 
    # without worrying about escaping quotes, newlines, or backslashes in Bash.
    export ARB_FILE="$1"
    export ARB_KEY="$2"
    export ARB_VALUE="$3"

    # Notice the quotes around 'EOF'. This prevents Bash from evaluating variables inside,
    # leaving Python to read them securely from os.environ.
    uv run python - <<'EOF'
import json
import os
import re
import sys

file_path = os.environ['ARB_FILE']
key = os.environ['ARB_KEY']
value = os.environ['ARB_VALUE']

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # FIX: Remove trailing commas (which are common in Dart/Flutter but invalid in strict JSON)
    content = re.sub(r',(\s*[}\]])', r'\1', content)

    # Parse as JSON to get existing data
    data = json.loads(content)
    
    # Add the new entry
    data[key] = value

    # Write back with proper formatting
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')

except json.JSONDecodeError as e:
    print(f"\n\033[0;31m[!] JSON Decode Error in {file_path}\033[0m", file=sys.stderr)
    print(f"\033[0;31m[!] Please check if the file has syntax errors (like missing quotes or comments).\033[0m", file=sys.stderr)
    print(f"\033[0;31m[!] Details: {e}\033[0m\n", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"\n\033[0;31m[!] Error: {e}\033[0m\n", file=sys.stderr)
    sys.exit(1)
EOF
}

# Add to French file
echo -e "${BLUE}Adding to app_fr.arb...${NC}"
add_to_arb "$FR_FILE" "$KEY_NAME" "$FR_STRING"

# Add to English file
echo -e "${BLUE}Adding to app_en.arb...${NC}"
add_to_arb "$EN_FILE" "$KEY_NAME" "$EN_STRING"

# Regenerate localization files
echo -e "${BLUE}Regenerating localization files...${NC}"
cd "$PROJECT_PATH"
flutter gen-l10n

echo -e "${GREEN}✓ Successfully added localization key: $KEY_NAME${NC}"
echo -e "${GREEN}  FR: $FR_STRING${NC}"
echo -e "${GREEN}  EN: $EN_STRING${NC}"
