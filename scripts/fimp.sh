#!/usr/bin/env bash
# =============================================================================
# fix_flutter_imports.sh
#
# Fixes broken Dart imports after files are moved. Two separate strategies:
#
#   lib/ files  -> broken relative import (./  or ../)
#                  -> search lib/ + test/ -> rewrite as new relative path
#
#   test/ files -> broken package: import (package:app_name/...)
#                  -> search lib/ first, then test/ as fallback
#                  -> rewrite as package:app_name/<new_path>
#
# All other import types (dart:, non-relative in lib/, etc.) are untouched.
# Package name is read automatically from pubspec.yaml.
#
# Usage:
#   ./fix_flutter_imports.sh            # fix in place
#   ./fix_flutter_imports.sh --dry-run  # preview only, no writes
# =============================================================================

set -euo pipefail

# -- Flags --------------------------------------------------------------------
DRY_RUN=false
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg  (supported: --dry-run)"; exit 1 ;;
  esac
done

# -- Colours ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ ok ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[warn]${RESET}  $*"; }
err()  { echo -e "${RED}[err ]${RESET}  $*"; }
skip() { echo -e "${YELLOW}[skip]${RESET}  $*"; }

# -- Sanity checks ------------------------------------------------------------
if ! command -v flutter &>/dev/null; then
  err "'flutter' not found in PATH."; exit 1
fi

# Find project root (directory containing pubspec.yaml)
PROJECT_ROOT=""
dir="$PWD"
while [[ "$dir" != "/" ]]; do
  [[ -f "$dir/pubspec.yaml" ]] && PROJECT_ROOT="$dir" && break
  dir="$(dirname "$dir")"
done
[[ -z "$PROJECT_ROOT" ]] && err "Could not find pubspec.yaml." && exit 1

# Canonicalise PROJECT_ROOT to avoid symlink/trailing-slash mismatches
PROJECT_ROOT="$(realpath "$PROJECT_ROOT")"

cd "$PROJECT_ROOT"
LIB_DIR="$PROJECT_ROOT/lib"
TEST_DIR="$PROJECT_ROOT/test"

[[ ! -d "$LIB_DIR" ]] && err "No lib/ directory found at $PROJECT_ROOT" && exit 1

# -- Read package name from pubspec.yaml --------------------------------------
PACKAGE_NAME=$(grep -E '^name:' "$PROJECT_ROOT/pubspec.yaml" \
  | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '[:space:]')

if [[ -z "$PACKAGE_NAME" ]]; then
  err "Could not read 'name:' from pubspec.yaml"
  exit 1
fi

log "Project root:  $PROJECT_ROOT"
log "Package name:  $PACKAGE_NAME"
[[ -d "$TEST_DIR" ]] && log "test/ folder found." || log "No test/ folder found."
[[ "$DRY_RUN" == true ]] && warn "DRY RUN -- no files will be modified."

# -- Run flutter analyze ------------------------------------------------------
log "Running flutter analyze..."
ANALYZE_OUTPUT=$(flutter analyze --no-pub 2>&1 || true)

# -- Helpers ------------------------------------------------------------------

# Find a dart file by basename, searching dirs in order, return candidates
find_candidates() {
  local basename="$1"
  shift
  local dirs=("$@")
  find "${dirs[@]}" -type f -name "$basename" 2>/dev/null \
    | while IFS= read -r p; do realpath "$p"; done \
    | sort
}

filter_empty() {
  local -n _arr=$1      # nameref — modifies caller's array in-place
  local _clean=()
  for _e in "${_arr[@]:-}"; do [[ -n "$_e" ]] && _clean+=("$_e"); done
  _arr=("${_clean[@]:-}")
}

# Apply a sed replacement safely via a temp file
apply_sed() {
  local file="$1" old="$2" new="$3"
  local escaped_old escaped_new tmp
  escaped_old=$(printf '%s\n' "$old" | sed 's/[\/&]/\\&/g')
  escaped_new=$(printf '%s\n' "$new" | sed 's/[\/&]/\\&/g')
  tmp=$(mktemp)
  sed "s|${escaped_old}|${escaped_new}|g" "$file" > "$tmp"
  mv "$tmp" "$file"
}

# -- Parse analyzer output ----------------------------------------------------
FIXES_APPLIED=0; FIXES_SKIPPED=0; FIXES_FAILED=0
PAIRS_SEEN=()

while IFS= read -r line; do

  # Match any broken-URI error line
  if [[ ! "$line" =~ (Target\ of\ URI\ doesn\'t\ exist|URI\ target\ doesn\'t\ exist):\ \'([^\']+\.dart)\' ]]; then
    continue
  fi
  BROKEN_IMPORT="${BASH_REMATCH[2]}"

  # Extract the importing file (lib/ or test/)
  if [[ ! "$line" =~ [[:space:]]+((lib|test)/[^:]+\.dart):[0-9]+:[0-9]+ ]]; then
    continue
  fi
  IMPORTER_REL="${BASH_REMATCH[1]}"
  IMPORTER_ABS="$PROJECT_ROOT/$IMPORTER_REL"

  # Deduplicate
  PAIR_KEY="${IMPORTER_ABS}||${BROKEN_IMPORT}"
  already_seen=false
  for seen in "${PAIRS_SEEN[@]:-}"; do
    [[ "$seen" == "$PAIR_KEY" ]] && already_seen=true && break
  done
  $already_seen && continue
  PAIRS_SEEN+=("$PAIR_KEY")

  TARGET_BASENAME=$(basename "$BROKEN_IMPORT")

  # ==========================================================================
  # CASE A: importer is in lib/ — expect a broken relative import
  # ==========================================================================
  if [[ "$IMPORTER_REL" == lib/* ]]; then

    # Skip anything that isn't a relative import
    if [[ "$BROKEN_IMPORT" != ./* ]] && [[ "$BROKEN_IMPORT" != ../* ]]; then
      continue
    fi

    # Search lib/ then test/
    SEARCH_DIRS=("$LIB_DIR")
    [[ -d "$TEST_DIR" ]] && SEARCH_DIRS+=("$TEST_DIR")
    mapfile -t CANDIDATES < <(find_candidates "$TARGET_BASENAME" "${SEARCH_DIRS[@]}")
    filter_empty CANDIDATES

    # Filter out empty strings
    REAL=()
    for c in "${CANDIDATES[@]:-}"; do [[ -n "$c" ]] && REAL+=("$c"); done
    CANDIDATES=("${REAL[@]:-}")
    COUNT=${#CANDIDATES[@]}

    if [[ $COUNT -eq 0 ]]; then
      skip "Not found: '$TARGET_BASENAME'  <-- $IMPORTER_REL"
      (( FIXES_FAILED++ )) || true; continue
    fi
    if [[ $COUNT -gt 1 ]]; then
      warn "Ambiguous: '$TARGET_BASENAME' matched $COUNT files, skipping:"
      for c in "${CANDIDATES[@]}"; do warn "    ${c#$PROJECT_ROOT/}"; done
      warn "    <-- $IMPORTER_REL"
      (( FIXES_SKIPPED++ )) || true; continue
    fi

    TARGET_ABS="${CANDIDATES[0]}"
    IMPORTER_DIR=$(dirname "$IMPORTER_ABS")

    NEW_IMPORT=$(uv run python -c "
import sys, os
target, importer_dir = sys.argv[1], sys.argv[2]
rel = os.path.relpath(target, importer_dir)
if not rel.startswith('..'):
    rel = './' + rel
print(rel)
" "$TARGET_ABS" "$IMPORTER_DIR")

  # ==========================================================================
  # CASE B: importer is in test/ — expect a broken package: import
  # ==========================================================================
  elif [[ "$IMPORTER_REL" == test/* ]]; then

    # Skip anything that isn't a package: import for this app
    if [[ "$BROKEN_IMPORT" != package:${PACKAGE_NAME}/* ]]; then
      continue
    fi

    # Search lib/ first, then test/ as fallback
    mapfile -t LIB_CANDIDATES  < <(find_candidates "$TARGET_BASENAME" "$LIB_DIR")
    mapfile -t TEST_CANDIDATES < <(
      if [[ -d "$TEST_DIR" ]]; then
        find_candidates "$TARGET_BASENAME" "$TEST_DIR"
      fi
    )
    filter_empty LIB_CANDIDATES
    filter_empty TEST_CANDIDATES

    # Filter out empty strings
    REAL_LIB=()
    for c in "${LIB_CANDIDATES[@]:-}"; do [[ -n "$c" ]] && REAL_LIB+=("$c"); done
    
    REAL_TEST=()
    for c in "${TEST_CANDIDATES[@]:-}"; do [[ -n "$c" ]] && REAL_TEST+=("$c"); done

    # Merge: lib/ results take priority; only add test/ results if lib/ empty
    if [[ ${#REAL_LIB[@]} -gt 0 ]]; then
      CANDIDATES=("${REAL_LIB[@]}")
    else
      CANDIDATES=("${REAL_TEST[@]:-}")
    fi
    COUNT=${#CANDIDATES[@]}

    if [[ $COUNT -eq 0 ]]; then
      skip "Not found: '$TARGET_BASENAME'  <-- $IMPORTER_REL"
      (( FIXES_FAILED++ )) || true; continue
    fi
    if [[ $COUNT -gt 1 ]]; then
      warn "Ambiguous: '$TARGET_BASENAME' matched $COUNT files, skipping:"
      for c in "${CANDIDATES[@]}"; do warn "    ${c#$PROJECT_ROOT/}"; done
      warn "    <-- $IMPORTER_REL"
      (( FIXES_SKIPPED++ )) || true; continue
    fi

    TARGET_ABS="${CANDIDATES[0]}"

    # FIXED — handles both lib/ and test/ correctly
    TARGET_REL="${TARGET_ABS#$PROJECT_ROOT/}"   # e.g. lib/widgets/foo.dart
    if [[ "$TARGET_REL" == lib/* ]]; then
      TARGET_FROM_PKG="${TARGET_REL#lib/}"      # e.g. widgets/foo.dart
    elif [[ "$TARGET_REL" == test/* ]]; then
      TARGET_FROM_PKG="${TARGET_REL#test/}"     # e.g. features/foo_test.dart
    else
      warn "Unexpected path '$TARGET_REL', skipping"
      (( FIXES_SKIPPED++ )) || true; continue
    fi
    NEW_IMPORT="package:${PACKAGE_NAME}/${TARGET_FROM_PKG}"

  else
    continue
  fi

  # -- Verify the import line exists before writing --------------------------
  if ! grep -qE "import ['\"].*${TARGET_BASENAME}['\"]" "$IMPORTER_ABS"; then
    skip "Import line not found in $IMPORTER_REL (may already be fixed)"
    continue
  fi

  # -- Apply or preview ------------------------------------------------------
  if [[ "$DRY_RUN" == true ]]; then
    ok "[dry-run] $IMPORTER_REL"
    echo -e "          ${RED}- $BROKEN_IMPORT${RESET}"
    echo -e "          ${GREEN}+ $NEW_IMPORT${RESET}"
  else
    apply_sed "$IMPORTER_ABS" "$BROKEN_IMPORT" "$NEW_IMPORT"
    ok "Fixed: $IMPORTER_REL"
    echo -e "       ${RED}- $BROKEN_IMPORT${RESET}"
    echo -e "       ${GREEN}+ $NEW_IMPORT${RESET}"
  fi

  (( FIXES_APPLIED++ )) || true

done <<< "$ANALYZE_OUTPUT"

# -- Summary ------------------------------------------------------------------
echo ""
echo -e "${BOLD}-- Summary ----------------------------------------------------------${RESET}"
echo -e "  ${GREEN}Fixed:${RESET}   $FIXES_APPLIED import(s)"
echo -e "  ${YELLOW}Skipped:${RESET} $FIXES_SKIPPED import(s)  (ambiguous filename)"
echo -e "  ${RED}Failed:${RESET}  $FIXES_FAILED import(s)  (file not found)"
echo ""

if [[ $FIXES_APPLIED -gt 0 ]] && [[ "$DRY_RUN" == false ]]; then
  log "Re-running flutter analyze to verify..."
  flutter analyze --no-pub 2>&1 | tail -5 || true
fi
