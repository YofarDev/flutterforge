#!/usr/bin/env bash
# =============================================================================
# fdead.sh
#
# Finds dead Dart files in a Flutter project — files that are never imported
# by anything, making them orphaned after refactors.
#
# Exclusions (never reported as dead):
#   - main.dart (app entry point)
#   - *_test.dart files (test entry points)
#   - *.g.dart / *.freezed.dart / *.gen.dart (generated files)
#   - Any file exported via a barrel file (index.dart or any *_exports.dart)
#
# Usage:
#   ./fdead.sh            # scan lib/ only
#   ./fdead.sh --test     # scan lib/ and test/
#   ./fdead.sh --clean-dead   # delete found dead files
#   ./fdead.sh --clean-empty  # delete empty directories (ignores .gitkeep)
# =============================================================================

set -euo pipefail

# -- Flags --------------------------------------------------------------------
INCLUDE_TEST=false
CLEAN_DEAD=false
CLEAN_EMPTY=false

for arg in "$@"; do
  case $arg in
    --test)        INCLUDE_TEST=true ;;
    --clean-dead)  CLEAN_DEAD=true ;;
    --clean-empty) CLEAN_EMPTY=true ;;
    *) echo "Unknown argument: $arg  (supported: --test, --clean-dead, --clean-empty)"; exit 1 ;;
  esac
done

# -- Colours ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ ok ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[warn]${RESET}  $*"; }
dead() { echo -e "  ${RED}✗${RESET}  $*"; }

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

# -- Step 1: collect all dart files to check ----------------------------------
SCAN_DIRS=("$LIB_DIR")
[[ "$INCLUDE_TEST" == true ]] && [[ -d "$TEST_DIR" ]] && SCAN_DIRS+=("$TEST_DIR")

mapfile -t ALL_DART_FILES < <(
  find "${SCAN_DIRS[@]}" -type f -name "*.dart" | sort
)

# -- Step 2: collect all import/export statements across the whole project ----
SEARCH_DIRS=("$LIB_DIR")
[[ -d "$TEST_DIR" ]] && SEARCH_DIRS+=("$TEST_DIR")

ALL_REFERENCES=$(
  grep -rh \
    -e "^import ['\"]" \
    -e "^export ['\"]" \
    -e "^part ['\"]" \
    "${SEARCH_DIRS[@]}" \
    --include="*.dart" 2>/dev/null || true
)

# -- Step 3: collect all files exported via barrel files ----------------------
mapfile -t BARREL_EXPORTS < <(
  grep -rh "^export ['\"]" "${SCAN_DIRS[@]}" --include="*.dart" 2>/dev/null \
  | grep -oE "['\"][^'\"]+\.dart['\"]" \
  | tr -d "'\"" \
  || true
)

is_barrel_exported() {
  local basename="$1"
  for export in "${BARREL_EXPORTS[@]:-}"; do
    [[ "$(basename "$export")" == "$basename" ]] && return 0
  done
  return 1
}

# -- Step 4: for each candidate file, check if it's referenced anywhere -------
DEAD_FILES=()
SKIPPED=0

for filepath in "${ALL_DART_FILES[@]}"; do
  filename=$(basename "$filepath")
  rel="${filepath#$PROJECT_ROOT/}"

  # -- Exclusions -------------------------------------------------------------
  if [[ "$filename" == "main.dart" ]] || \
     [[ "$filename" == *_test.dart ]] || \
     [[ "$filename" == *.g.dart ]] || \
     [[ "$filename" == *.freezed.dart ]] || \
     [[ "$filename" == *.gen.dart ]] || \
     is_barrel_exported "$filename"; then
    
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # -- Check if filename appears in any import/export/part --------------------
  if echo "$ALL_REFERENCES" | grep -qF "$filename"; then
    continue
  fi

  DEAD_FILES+=("$rel")
done

# -- Step 5: report and remove dead files -------------------------------------
echo ""
TOTAL=${#ALL_DART_FILES[@]}
DEAD_COUNT=${#DEAD_FILES[@]}
CHECKED=$(( TOTAL - SKIPPED ))

echo -e "${BOLD}-- Dead Files -------------------------------------------------------${RESET}"

if [[ $DEAD_COUNT -eq 0 ]]; then
  ok "No dead files found. All $CHECKED checked files are referenced."
else
  echo -e "  ${RED}${BOLD}$DEAD_COUNT dead file(s) found:${RESET}"
  echo ""

  current_dir=""
  for f in "${DEAD_FILES[@]}"; do
    dir=$(dirname "$f")
    if [[ "$dir" != "$current_dir" ]]; then
      echo -e "  ${DIM}$dir/${RESET}"
      current_dir="$dir"
    fi
    dead "$(basename "$f")"
  done

  if [[ "$CLEAN_DEAD" == true ]]; then
    echo ""
    REMOVED_FILES=0
    for f in "${DEAD_FILES[@]}"; do
      if rm -f "$PROJECT_ROOT/$f"; then
        ok "Removed  $f"
        REMOVED_FILES=$((REMOVED_FILES + 1))
      fi
    done
    
    echo ""
    if [[ $REMOVED_FILES -gt 0 ]]; then
      ok "$REMOVED_FILES file(s) removed."
    else
      warn "No files could be removed."
    fi
  else
    echo ""
    echo -e "${DIM}  Tip: run with --clean-dead to delete these files.${RESET}"
  fi
fi

# -- Step 6: find empty directories in lib/ -----------------------------------
# (We run this after removing dead files so newly emptied dirs are caught)
EMPTY_DIRS=()
while IFS= read -r -d '' d; do
  # Exclude .gitkeep from making a directory "not empty"
  if [[ -z "$(find "$d" -mindepth 1 -type f ! -name ".gitkeep" -print -quit)" ]]; then
    EMPTY_DIRS+=("${d#$PROJECT_ROOT/}")
  fi
done < <(find "$LIB_DIR" -mindepth 1 -type d -print0 | sort -rz)

EMPTY_COUNT=${#EMPTY_DIRS[@]}

# -- Step 7: report and remove empty directories ------------------------------
echo ""
echo -e "${BOLD}-- Empty Directories in lib/ ----------------------------------------${RESET}"

if [[ $EMPTY_COUNT -eq 0 ]]; then
  ok "No empty directories found in lib/."
else
  echo -e "  ${YELLOW}${BOLD}$EMPTY_COUNT empty director$([ $EMPTY_COUNT -eq 1 ] && echo y || echo ies) found:${RESET}"
  echo ""
  for d in "${EMPTY_DIRS[@]}"; do
    echo -e "  ${YELLOW}⊘${RESET}  ${DIM}$d/${RESET}"
  done

  if [[ "$CLEAN_EMPTY" == true ]]; then
    echo ""
    REMOVED=0
    while IFS= read -r -d '' d; do
      rel="${d#$PROJECT_ROOT/}"
      # Same emptiness check: contains no files (excluding .gitkeep)
      if [[ -z "$(find "$d" -mindepth 1 -type f ! -name ".gitkeep" -print -quit)" ]]; then
        # Delete .gitkeep first if it exists so rmdir will succeed
        rm -f "$d/.gitkeep"
        if rmdir "$d" 2>/dev/null; then
          ok "Removed  $rel/"
          REMOVED=$((REMOVED + 1))
        fi
      fi
    done < <(find "$LIB_DIR" -mindepth 1 -type d -depth -print0)
    
    echo ""
    if [[ $REMOVED -gt 0 ]]; then
      ok "$REMOVED director$([ $REMOVED -eq 1 ] && echo y || echo ies) removed."
    else
      warn "No directories could be removed."
    fi
  else
    echo ""
    echo -e "${DIM}  Tip: run with --clean-empty to delete these directories.${RESET}"
  fi
fi

echo ""
echo -e "${DIM}  Scanned $CHECKED files  •  Skipped $SKIPPED (main/tests/generated/barrel-exported)  •  $EMPTY_COUNT empty dir(s)${RESET}"
echo ""