#!/usr/bin/env bash
# Install the /delegate skill at user level: ~/.claude/skills/delegate/{SKILL.md,delegate-run.sh}
# Safe by design: never deletes anything, never edits settings.json, refuses to overwrite a different existing file
# unless --force (then keeps a timestamped backup next to it). If any file would be refused, NOTHING is changed.
# Files are replaced with mv, never rewritten in place, so a delegate-run.sh that is running keeps reading its old copy.
#
# Usage:  bash install.sh [--force]
# Override the target with:  CLAUDE_HOME=/some/dir bash install.sh
set -eu

FORCE=0
if [ "${1:-}" = "--force" ]; then FORCE=1; fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_ROOT="${CLAUDE_HOME:-$HOME/.claude}"
DEST_DIR="$TARGET_ROOT/skills/delegate"
FILES="SKILL.md delegate-run.sh"

for f in $FILES; do
  if [ ! -f "$SRC_DIR/delegate/$f" ]; then
    echo "ERROR: $SRC_DIR/delegate/$f not found. Run this script from inside the unzipped kit folder." >&2
    exit 1
  fi
done

if [ -f "$SRC_DIR/VERSION" ]; then
  echo "Kit version: $(cat "$SRC_DIR/VERSION")"
fi

# pass 1: decide, change nothing
REFUSED=0
for f in $FILES; do
  if [ -f "$DEST_DIR/$f" ] && ! cmp -s "$SRC_DIR/delegate/$f" "$DEST_DIR/$f"; then
    if [ "$FORCE" -eq 0 ]; then
      echo "A different $f already exists at $DEST_DIR/$f" >&2
      echo "  compare with:  diff \"$DEST_DIR/$f\" \"$SRC_DIR/delegate/$f\"" >&2
      REFUSED=1
    fi
  fi
done
if [ "$REFUSED" -eq 1 ]; then
  echo "Nothing was changed. Re-run with --force to replace (a backup of each replaced file will be kept)." >&2
  exit 2
fi

if pgrep -f "[d]elegate-run.sh codex" > /dev/null 2>&1; then
  echo "Note: a /delegate Codex run is active. It keeps its current helper, but its later steps will use the new files." >&2
  echo "      Installing between runs is safer." >&2
fi

# pass 2: install (copy to a temp file next to the target, then mv: a running script keeps its old file)
mkdir -p "$DEST_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
for f in $FILES; do
  SRC="$SRC_DIR/delegate/$f"
  DEST="$DEST_DIR/$f"
  if [ -f "$DEST" ]; then
    if cmp -s "$SRC" "$DEST"; then
      echo "Already up to date: $DEST"
    else
      cp "$DEST" "$DEST.bak-$STAMP"
      cp "$SRC" "$DEST.tmp-$$"
      mv -f "$DEST.tmp-$$" "$DEST"
      echo "Replaced $DEST (previous version saved as $DEST.bak-$STAMP)"
    fi
  else
    cp "$SRC" "$DEST.tmp-$$"
    mv -f "$DEST.tmp-$$" "$DEST"
    echo "Installed $DEST"
  fi
done

echo
echo "Installed helper check: $(bash "$DEST_DIR/delegate-run.sh" version)"

SNIP="$SRC_DIR/settings.snippet.json"
echo
echo "Next: add the permission rules from $SNIP to $TARGET_ROOT/settings.json."
echo "  Safe automatic merge (backs up first, never removes or overwrites your entries):"
echo "    node \"$SRC_DIR/merge-settings.js\" --dry-run     # preview"
echo "    node \"$SRC_DIR/merge-settings.js\"               # apply"
echo
echo "Optional self-test of the helper script (fake Codex, about 15 seconds):  bash \"$SRC_DIR/tests/run_tests.sh\""
echo
echo "Then, in any git repo:  cd <repo>; claude; /delegate <task>"
