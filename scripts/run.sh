#!/bin/bash
# Launch the mod (you + 2 AIs from start.txt). Detached; returns immediately.
. "$(dirname "$0")/common.sh"
cd "$BAR_DIR"
START="${1:-$SCRIPTS_DIR/start.txt}"  # 1 human + 2 BARb AIs; pass another script to override
setsid "$ENGINE" --write-dir "$BAR_DIR" "$START" >/dev/null 2>&1 &
echo "started (pid $!)"
