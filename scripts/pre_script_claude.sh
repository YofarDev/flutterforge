#!/bin/bash
set -e

# Resolve flutterforge root dynamically based on script location
FLUTTERFORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$FLUTTERFORGE_ROOT/.claude/skills"

echo "Pulling latest flutterforge..."
PULL_OUTPUT=$(git -C "$FLUTTERFORGE_ROOT" pull)
echo "$PULL_OUTPUT"

if echo "$PULL_OUTPUT" | grep -q "Already up to date."; then
  echo "No changes pulled, skipping skill sync."
  exit 0
fi

echo "Syncing skills to ~/.claude/skills/..."
for skill in "$SKILLS_SRC"/*/; do
  rm -rf ~/.claude/skills/$(basename "$skill")
  cp -r "$skill" ~/.claude/skills/$(basename "$skill")
done

echo "Done! Skills synced:"
ls ~/.claude/skills/