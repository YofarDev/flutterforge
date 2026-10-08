#!/bin/bash
set -e

# Resolve flutterforge root dynamically based on script location
FLUTTERFORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Pulling latest flutterforge..."
PULL_OUTPUT=$(git -C "$FLUTTERFORGE_ROOT" pull)
echo "$PULL_OUTPUT"

if echo "$PULL_OUTPUT" | grep -q "Already up to date."; then
  echo "No changes pulled, skipping skill sync."
  exit 0
fi

echo "Syncing skills to user-level skill folders..."
# .agents/skills is the single source of truth; sync_skills.sh propagates it
# to .codex/ and (with --user) ~/.agents/skills + ~/.claude/skills
bash "$FLUTTERFORGE_ROOT/scripts/sync_skills.sh" --user

echo "Done!"
