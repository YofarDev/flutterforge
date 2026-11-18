#!/bin/bash
set -e

# Resolve flutterforge root dynamically based on script location
FLUTTERFORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Pulling latest flutterforge..."
# Compare HEAD before/after instead of parsing git's (localized) message, and
# never fail the hook when offline: a failed pull just skips the sync.
BEFORE="$(git -C "$FLUTTERFORGE_ROOT" rev-parse HEAD)"
if ! git -C "$FLUTTERFORGE_ROOT" pull; then
  echo "git pull failed (offline?) — skipping skill sync."
  exit 0
fi
if [ "$(git -C "$FLUTTERFORGE_ROOT" rev-parse HEAD)" = "$BEFORE" ]; then
  echo "No changes pulled, skipping skill sync."
  exit 0
fi

echo "Syncing skills to user-level skill folders..."
# .agents/skills is the single source of truth; sync_skills.sh propagates it
# to .codex/ and (with --user) ~/.agents/skills + ~/.claude/skills
bash "$FLUTTERFORGE_ROOT/scripts/sync_skills.sh" --user

echo "Done!"
