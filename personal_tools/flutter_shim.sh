#!/usr/bin/env bash
# =============================================================================
# flutter_shim.sh — a `flutter` placed ahead of the real SDK on PATH that sends
# `flutter test` and `flutter analyze` through the machine-wide queue.
#
# Agents in several projects often start test runs at the same moment; each
# run spawns a pool of test processes and an analyzer, and the machine
# freezes. FlutterForge apps queue their own runs (scripts/ftest.sh,
# scripts/fverify.sh), but a bare `flutter test` would skip that. This shim
# makes every bare run wait for the same slot (scripts/fqueue.sh in this
# repository, lock in ~/.cache/flutterforge/test-queue) and run niced —
# for every project on the machine, FlutterForge or not.
#
# Everything else (`flutter run`, `pub get`, `build`, `--version`, ...) and
# `analyze --watch` go straight to the real flutter with `exec`. A command
# already inside a queued run (FQUEUE_HELD=1, e.g. fverify) is not queued
# again. IDEs that call the SDK by absolute path are unaffected.
#
# Install: personal_tools/install_flutter_shim.sh (symlinks this file as
# ~/.flutterforge/bin/flutter; that directory must come first on PATH).
# Environment: FLUTTER_REAL=<path> to name the real flutter explicitly;
# FORGE_QUEUE=0, FORGE_QUEUE_SLOTS, FORGE_NICE as in scripts/fqueue.sh.
# Bash 3.2 compatible.
# =============================================================================

set -u

# Resolves symlinks without `readlink -f` (absent on older macOS).
resolve() {
  local path="$1" target
  while [ -L "$path" ]; do
    target="$(readlink "$path")"
    case "$target" in
      /*) path="$target" ;;
      *) path="$(dirname "$path")/$target" ;;
    esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd -P)" "$(basename "$path")"
}

SELF="$(resolve "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"

REAL="${FLUTTER_REAL:-}"
if [ -z "$REAL" ]; then
  OLD_IFS="$IFS"
  IFS=:
  for dir in $PATH; do
    candidate="$dir/flutter"
    if [ -x "$candidate" ] && [ ! -d "$candidate" ] && [ "$(resolve "$candidate")" != "$SELF" ]; then
      REAL="$candidate"
      break
    fi
  done
  IFS="$OLD_IFS"
fi
if [ -z "$REAL" ]; then
  echo "flutter shim: no real flutter found on PATH after $SELF (set FLUTTER_REAL)." >&2
  exit 127
fi

# The subcommand is the first argument that is not a global option.
# Test runs scoped to existing paths use the light lane (see fqueue.sh).
SUBCOMMAND=""
WATCH=false
LANE=heavy
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=true ;;
    -*) ;;
    *)
      if [ -z "$SUBCOMMAND" ]; then
        SUBCOMMAND="$arg"
      elif [ -e "$arg" ]; then
        LANE=light
      fi
      ;;
  esac
done
[ "$SUBCOMMAND" = test ] || LANE=heavy

case "$SUBCOMMAND" in
  test|analyze) ;;
  *) exec "$REAL" "$@" ;;
esac
if [ "$WATCH" = true ] || [ "${FQUEUE_HELD:-0}" = "1" ] || [ "${FORGE_QUEUE:-1}" = "0" ] \
  || [ ! -f "$REPO_ROOT/scripts/fqueue.sh" ]; then
  exec "$REAL" "$@"
fi

# shellcheck source=../scripts/fqueue.sh
. "$REPO_ROOT/scripts/fqueue.sh"
fqueue_acquire "flutter $SUBCOMMAND" "$LANE"
fqueue_nice "$REAL" "$@"
