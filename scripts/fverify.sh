#!/usr/bin/env bash
# =============================================================================
# fverify.sh — one-command quality gate to run before finishing a change.
#
# Runs, in order:
#   1. flutter analyze
#   2. flutter test   (includes the architecture boundary + DI smoke tests)
#
# Exits non-zero if either step fails. Extra arguments are forwarded to
# `flutter test` (e.g. `fverify.sh --update-coverage`).
#
# Usage:
#   ./scripts/fverify.sh
#   fverify                 # if aliased
# =============================================================================

set -euo pipefail

# -- Colours ------------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

step()  { echo -e "\n${CYAN}[verify]${RESET} $*"; }
ok()    { echo -e "${GREEN}[ ok  ]${RESET} $*"; }
fail()  { echo -e "${RED}[fail ]${RESET} $*"; }

# -- Find project root --------------------------------------------------------
PROJECT_ROOT=""
dir="$PWD"
while [[ "$dir" != "/" ]]; do
  [[ -f "$dir/pubspec.yaml" ]] && PROJECT_ROOT="$dir" && break
  dir="$(dirname "$dir")"
done
[[ -z "$PROJECT_ROOT" ]] && fail "Could not find pubspec.yaml." && exit 1
cd "$PROJECT_ROOT"

START_TS=$SECONDS

# -- 1. Static analysis ---------------------------------------------------------
step "flutter analyze"
if flutter analyze --no-pub; then
  ok "analyze clean"
else
  fail "flutter analyze reported issues — fix them before finishing."
  exit 1
fi

# -- 2. Tests -------------------------------------------------------------------
step "flutter test $*"
if flutter test "$@"; then
  ok "all tests passed"
else
  fail "flutter test failed — fix failing tests before finishing."
  exit 1
fi

ELAPSED=$((SECONDS - START_TS))
echo ""
echo -e "${BOLD}-- verify -----------------------------------------------------------${RESET}"
echo -e "  ${GREEN}analyze ✓   test ✓   (${ELAPSED}s)${RESET}"
echo -e "  ${GREEN}Ready to finish.${RESET}"
echo ""
