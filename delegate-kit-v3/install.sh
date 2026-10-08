#!/usr/bin/env bash
# Install the /delegate skill at user level (~/.claude/skills/delegate/SKILL.md).
# Safe by design: never deletes anything, never edits settings.json, refuses to overwrite a different
# existing SKILL.md unless --force (then keeps a timestamped backup next to it).
#
# Usage:  bash install.sh [--force]
# Override the target with:  CLAUDE_HOME=/some/dir bash install.sh
set -eu

FORCE=0
if [ "${1:-}" = "--force" ]; then FORCE=1; fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SRC_DIR/delegate/SKILL.md"
TARGET_ROOT="${CLAUDE_HOME:-$HOME/.claude}"
DEST_DIR="$TARGET_ROOT/skills/delegate"
DEST="$DEST_DIR/SKILL.md"

if [ ! -f "$SRC" ]; then
  echo "ERROR: $SRC not found. Run this script from inside the unzipped kit folder." >&2
  exit 1
fi

if [ -f "$SRC_DIR/VERSION" ]; then
  echo "Kit version: $(cat "$SRC_DIR/VERSION")"
fi

mkdir -p "$DEST_DIR"

if [ -f "$DEST" ]; then
  if cmp -s "$SRC" "$DEST"; then
    echo "Already up to date: $DEST"
  elif [ "$FORCE" -eq 1 ]; then
    BAK="$DEST.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$DEST" "$BAK"
    cp "$SRC" "$DEST"
    echo "Replaced $DEST (previous version saved as $BAK)"
  else
    echo "A different SKILL.md already exists at $DEST" >&2
    echo "Nothing was changed. Compare with:  diff \"$DEST\" \"$SRC\"" >&2
    echo "Re-run with --force to replace it (a backup will be kept)." >&2
    exit 2
  fi
else
  cp "$SRC" "$DEST"
  echo "Installed $DEST"
fi

SNIP="$SRC_DIR/settings.snippet.json"
echo
echo "Next: add the permission rules from $SNIP to $TARGET_ROOT/settings.json."
echo "  Safe automatic merge (backs up first, never removes or overwrites your entries):"
echo "    node \"$SRC_DIR/merge-settings.js\" --dry-run     # preview"
echo "    node \"$SRC_DIR/merge-settings.js\"               # apply"
echo
echo "Then, in any git repo:  cd <repo>; claude; /delegate <task>"
