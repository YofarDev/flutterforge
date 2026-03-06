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

L10N_DIR="$PROJECT_PATH/lib/l10n"
FR_FILE="$L10N_DIR/app_fr.arb"
EN_FILE="$L10N_DIR/app_en.arb"

# Check if files exist
if [ ! -f "$FR_FILE" ]; then
    echo -e "${RED}Error: French ARB file not found at $FR_FILE${NC}"
    exit 1
fi

if [ ! -f "$EN_FILE" ]; then
    echo -e "${RED}Error: English ARB file not found at $EN_FILE${NC}"
    exit 1
fi

# Escape strings for JSON
escape_json() {
    local string="$1"
    # Escape backslashes, quotes, and newlines
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    string="${string//$'\r'/\\r}"
    string="${string//$'\t'/\\t}"
    printf '%s' "$string"
}

FR_ESCAPED=$(escape_json "$FR_STRING")
EN_ESCAPED=$(escape_json "$EN_STRING")

# Function to add entry to ARB file
add_to_arb() {
    local file="$1"
    local key="$2"
    local value="$3"

    # Use Python to handle this portably
    python3 - <<PYTHON_SCRIPT
import json

file_path = "$file"
key = "$key"
value = """$value""".replace('\\n', '\n').replace('\\t', '\t').replace('\\r', '\r').replace('\\"', '"')

# Read the existing ARB file
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Parse as JSON to get existing data
data = json.loads(content)

# Add the new entry
data[key] = value

# Write back with proper formatting
with open(file_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PYTHON_SCRIPT
}

# Add to French file
echo -e "${BLUE}Adding to app_fr.arb...${NC}"
add_to_arb "$FR_FILE" "$KEY_NAME" "$FR_ESCAPED"

# Add to English file
echo -e "${BLUE}Adding to app_en.arb...${NC}"
add_to_arb "$EN_FILE" "$KEY_NAME" "$EN_ESCAPED"

# Regenerate localization files
echo -e "${BLUE}Regenerating localization files...${NC}"
cd "$PROJECT_PATH"
flutter gen-l10n

echo -e "${GREEN}✓ Successfully added localization key: $KEY_NAME${NC}"
echo -e "${GREEN}  FR: $FR_STRING${NC}"
echo -e "${GREEN}  EN: $EN_STRING${NC}"
