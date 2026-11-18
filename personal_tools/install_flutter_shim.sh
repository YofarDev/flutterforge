#!/usr/bin/env bash
# =============================================================================
# install_flutter_shim.sh — put personal_tools/flutter_shim.sh first on PATH as
# `flutter`, so every `flutter test` / `flutter analyze` on this machine waits
# for the shared test queue (see flutter_shim.sh).
#
#   personal_tools/install_flutter_shim.sh            # install / refresh
#   personal_tools/install_flutter_shim.sh --check    # report status only
#   personal_tools/install_flutter_shim.sh --remove   # uninstall
#
# Creates ~/.flutterforge/bin/flutter -> this repository's flutter_shim.sh and
# appends one PATH line to ~/.zshrc (and ~/.bashrc when it exists) — last, so
# it lands ahead of the SDK. New shells (and new agent sessions) pick it up.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SHIM="$SCRIPT_DIR/flutter_shim.sh"
BIN_DIR="$HOME/.flutterforge/bin"
LINK="$BIN_DIR/flutter"
MARKER="# flutterforge: queue flutter test/analyze machine-wide"
PATH_LINE='export PATH="$HOME/.flutterforge/bin:$PATH"'

rc_files() {
  echo "$HOME/.zshrc"
  [ -f "$HOME/.bashrc" ] && echo "$HOME/.bashrc"
  return 0
}

case "${1:-}" in
  --check)
    if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$SHIM" ]; then
      echo "link:  $LINK -> $SHIM"
    else
      echo "link:  missing"
    fi
    for rc in $(rc_files); do
      grep -qF "$MARKER" "$rc" 2>/dev/null && echo "path:  $rc ok" || echo "path:  $rc missing"
    done
    echo "now:   $(command -v flutter)"
    exit 0
    ;;
  --remove)
    rm -f "$LINK"
    for rc in $(rc_files); do
      if grep -qF "$MARKER" "$rc" 2>/dev/null; then
        tmp="$(mktemp)"
        grep -vF -e "$MARKER" -e "$PATH_LINE" "$rc" > "$tmp" || true
        cat "$tmp" > "$rc"
        rm -f "$tmp"
        echo "removed PATH line from $rc"
      fi
    done
    echo "Uninstalled. Open a new shell."
    exit 0
    ;;
  "") ;;
  *) echo "usage: $0 [--check|--remove]" >&2; exit 2 ;;
esac

chmod +x "$SHIM"
mkdir -p "$BIN_DIR"
ln -sfn "$SHIM" "$LINK"
echo "linked $LINK -> $SHIM"
for rc in $(rc_files); do
  if grep -qF "$MARKER" "$rc" 2>/dev/null; then
    echo "PATH already set in $rc"
  else
    printf '\n%s\n%s\n' "$MARKER" "$PATH_LINE" >> "$rc"
    echo "added PATH line to $rc"
  fi
done
echo "Done. New shells and agent sessions use the shim; check with: flutter --version && which flutter"
