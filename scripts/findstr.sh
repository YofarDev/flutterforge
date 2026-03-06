#!/usr/bin/env bash
# =============================================================================
# fl10n.sh
#
# Scans Flutter Dart files for hardcoded user-visible strings that should
# be localized via AppLocalizations.
#
# Skips:
#   - Already localized strings (AppLocalizations.of(context).xxx)
#   - AppLogger calls (debug / info / warning / error)
#   - Route strings starting with /
#   - Asset paths starting with assets/
#   - All-lowercase / snake_case strings (keys, enums, identifiers)
#   - Single chars, empty strings, pure numbers
#   - Imports, comments, technical strings (package:, dart:, http, RegExp…)
#   - Generated files (*.g.dart, *.freezed.dart)
#
# Usage:
#   ./fl10n.sh              # scan lib/
#   ./fl10n.sh --test       # scan lib/ + test/
# =============================================================================

set -euo pipefail

# -- Flags --------------------------------------------------------------------
INCLUDE_TEST=false
for arg in "$@"; do
  case $arg in
    --test) INCLUDE_TEST=true ;;
    *) echo "Unknown argument: $arg  (supported: --test)"; exit 1 ;;
  esac
done

# -- Colours ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ ok ]${RESET}  $*"; }

# -- Find project root --------------------------------------------------------
PROJECT_ROOT=""
dir="$PWD"
while [[ "$dir" != "/" ]]; do
  [[ -f "$dir/pubspec.yaml" ]] && PROJECT_ROOT="$dir" && break
  dir="$(dirname "$dir")"
done
[[ -z "$PROJECT_ROOT" ]] && echo "Could not find pubspec.yaml." && exit 1

cd "$PROJECT_ROOT"
LIB_DIR="$PROJECT_ROOT/lib"
TEST_DIR="$PROJECT_ROOT/test"

[[ ! -d "$LIB_DIR" ]] && echo "No lib/ directory found." && exit 1

log "Project root: $PROJECT_ROOT"
[[ "$INCLUDE_TEST" == true ]] && log "Scanning lib/ and test/" \
                               || log "Scanning lib/ only  (use --test to include test/)"

# -- Collect dart files -------------------------------------------------------
SCAN_DIRS=("$LIB_DIR")
[[ "$INCLUDE_TEST" == true ]] && [[ -d "$TEST_DIR" ]] && SCAN_DIRS+=("$TEST_DIR")

mapfile -t DART_FILES < <(
  find "${SCAN_DIRS[@]}" -type f -name "*.dart" \
  ! -path "*/l10n/*" \
  ! -name "*.g.dart" \
    ! -name "*.freezed.dart" \
    ! -name "*.gen.dart" \
  | sort
)

log "Found ${#DART_FILES[@]} dart files to scan."
echo ""

# -- Core scanning logic (Python for reliability) -----------------------------
# Bash string processing is too fragile for multi-quote, multi-line dart code.
# Python handles it cleanly with proper line context.

RESULTS=$(python3 << 'PYEOF'
import re
import os
import sys

PROJECT_ROOT = os.environ.get("PROJECT_ROOT", os.getcwd())

# Files passed via env (newline-separated)
dart_files_raw = os.environ.get("DART_FILES", "")
dart_files = [f for f in dart_files_raw.split("\n") if f.strip()]

# ── Skip rules ────────────────────────────────────────────────────────────────

# Lines containing these patterns are skipped entirely
SKIP_LINE_PATTERNS = [
    r"^\s*//",                          # single-line comment
    r"^\s*\*",                          # block comment line
    r"^\s*import\s+['\"]",             # import statement
    r"^\s*export\s+['\"]",             # export statement
    r"^\s*part\s+['\"]",               # part statement
    r"AppLogger\.(debug|info|warning|error)", # logger calls
    r"AppLocalizations\.of\(context\)\.", # already localized
    r"package:[a-z]",                   # package: references
    r"dart:[a-z]",                      # dart: references
    r"\.dart['\"]",                     # .dart file references
    r"RegExp\(",                        # regex patterns
    r"Uri\.",                           # URI construction
    r"https?://",                       # URLs
    r"^\s*#",                           # directives
    r"debugPrint\(",                    # debug prints
    r"print\(",                         # plain prints
    r"throw\s+",                        # thrown exceptions (usually dev-facing)
    r"assert\(",                        # assertions
]

# String values matching these are skipped
def should_skip_value(s):
    if not s or len(s) <= 1:
        return True  # empty or single char
    if s.startswith("$"):
        return True
    if re.fullmatch(r"[0-9.]+", s):
        return True  # pure number
    if re.fullmatch(r"[a-z0-9_]+", s):
        return True  # snake_case / all lowercase (key or enum)
    if s.startswith("/"):
        return True  # route string
    if s.startswith("assets/"):
        return True  # asset path
    if s.startswith("#") and re.fullmatch(r"#[0-9a-fA-F]{3,8}", s):
        return True  # hex colour
    if re.fullmatch(r"[\W_]+", s):
        return True  # only symbols/punctuation
    if re.fullmatch(r"[A-Z_]+", s):
        return True  # SCREAMING_SNAKE_CASE constant
    if re.fullmatch(r"\x1B\[[0-9;]*m", s):
        return True  # ANSI escape code
    if re.fullmatch(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", s):
        return True  # email pattern
    return False

findings = []  # list of (rel_path, line_number, string_value)

for filepath in dart_files:
    rel = filepath.replace(PROJECT_ROOT + "/", "")
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        continue

    # Track whether we're inside an AppLogger call block (multi-line)
    in_logger_call = False
    # Track whether we're inside a block comment
    in_block_comment = False

    for lineno, raw_line in enumerate(lines, start=1):
        line = raw_line.rstrip()

        # Block comment tracking
        if "/*" in line:
            in_block_comment = True
        if "*/" in line:
            in_block_comment = False
            continue
        if in_block_comment:
            continue

        # Multi-line logger call tracking
        if re.search(r"AppLogger\.(debug|info|warning|error)\s*\(", line):
            in_logger_call = True
        if in_logger_call:
            if ")" in line:
                in_logger_call = False
            continue

        # Skip line entirely if it matches any skip pattern
        skip = False
        for pattern in SKIP_LINE_PATTERNS:
            if re.search(pattern, line):
                skip = True
                break
        if skip:
            continue

        # Extract all string literals from the line
        # Match both single and double quoted strings (non-greedy, no newlines)
        # Also handles adjacent string literals
        for match in re.finditer(r"""(?<!['\"])(['"])((?:(?!\1)[^\\]|\\.)*)(\1)""", line):
            value = match.group(2)

            # Unescape common escape sequences for value inspection
            display = value.replace("\\n", " ").replace("\\t", " ").strip()

            if should_skip_value(display):
                continue

            findings.append((rel, lineno, display))

# Output: one result per line, tab-separated
for rel, lineno, value in findings:
    print(f"{rel}\t{lineno}\t{value}")

PYEOF
)

# Export vars for Python
export PROJECT_ROOT
export DART_FILES
RESULTS=$(DART_FILES="$(printf '%s\n' "${DART_FILES[@]}")" \
  PROJECT_ROOT="$PROJECT_ROOT" \
  python3 << 'PYEOF'
import re
import os

PROJECT_ROOT = os.environ.get("PROJECT_ROOT", os.getcwd())
dart_files_raw = os.environ.get("DART_FILES", "")
dart_files = [f for f in dart_files_raw.split("\n") if f.strip()]

SKIP_LINE_PATTERNS = [
    r"^\s*//",
    r"^\s*\*",
    r"^\s*import\s+['\"]",
    r"^\s*export\s+['\"]",
    r"^\s*part\s+['\"]",
    r"AppLogger\.(debug|info|warning|error)",
    r"AppLocalizations\.of\(context\)\.",
    r"package:[a-z]",
    r"dart:[a-z]",
    r"\.dart['\"]",
    r"RegExp\(",
    r"Uri\.",
    r"https?://",
    r"debugPrint\(",
    r"print\(",
    r"throw\s+",
    r"assert\(",
]

def should_skip_value(s):
    if not s or len(s) <= 1:
        return True
    if s.startswith("$"):
        return True
    if re.fullmatch(r"[0-9.]+", s):
        return True
    if re.fullmatch(r"[a-z0-9_]+", s):
        return True
    if s.startswith("/"):
        return True
    if s.startswith("assets/"):
        return True
    if s.startswith("#") and re.fullmatch(r"#[0-9a-fA-F]{3,8}", s):
        return True
    if re.fullmatch(r"[\W_]+", s):
        return True
    if re.fullmatch(r"[A-Z_]+", s):
        return True
    if re.fullmatch(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", s):
        return True
    return False

findings = []

for filepath in dart_files:
    rel = filepath.replace(PROJECT_ROOT + "/", "")
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        continue

    in_logger_call = False
    in_block_comment = False

    for lineno, raw_line in enumerate(lines, start=1):
        line = raw_line.rstrip()

        if "/*" in line:
            in_block_comment = True
        if "*/" in line:
            in_block_comment = False
            continue
        if in_block_comment:
            continue

        if re.search(r"AppLogger\.(debug|info|warning|error)\s*\(", line):
            in_logger_call = True
        if in_logger_call:
            if ")" in line:
                in_logger_call = False
            continue

        skip = False
        for pattern in SKIP_LINE_PATTERNS:
            if re.search(pattern, line):
                skip = True
                break
        if skip:
            continue

        for match in re.finditer(r"""(['"])((?:(?!\1)[^\\]|\\.)*)(\1)""", line):
            value = match.group(2)
            display = value.replace("\\n", " ").replace("\\t", " ").strip()
            if should_skip_value(display):
                continue
            findings.append((rel, lineno, display))

for rel, lineno, value in findings:
    print(f"{rel}\t{lineno}\t{value}")
PYEOF
)

# -- Format and display results -----------------------------------------------
TOTAL_FINDINGS=0
CURRENT_FILE=""

while IFS=$'\t' read -r filepath lineno value; do
  [[ -z "$filepath" ]] && continue
  (( TOTAL_FINDINGS++ )) || true

  if [[ "$filepath" != "$CURRENT_FILE" ]]; then
    echo -e "  ${BOLD}${CYAN}$filepath${RESET}"
    CURRENT_FILE="$filepath"
  fi

  echo -e "    ${DIM}L${lineno}${RESET}  ${YELLOW}\"$value\"${RESET}"

done <<< "$RESULTS"

# -- Summary ------------------------------------------------------------------
echo ""
echo -e "${BOLD}-- Summary ----------------------------------------------------------${RESET}"
if [[ $TOTAL_FINDINGS -eq 0 ]]; then
  ok "No unlocalized strings found."
else
  echo -e "  ${YELLOW}${BOLD}$TOTAL_FINDINGS potential unlocalized string(s) found.${RESET}"
  echo -e "  ${DIM}Review each — some may be intentional (error codes, formats, etc.)${RESET}"
fi
echo ""
