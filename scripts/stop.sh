#!/bin/bash
# Stop the running game.
. "$(dirname "$0")/common.sh"
pids=$(pgrep -f "^$ENGINE")
[ -z "$pids" ] && { echo "not running"; exit 0; }
kill $pids && echo "stopped $pids"
for _ in $(seq 20); do pgrep -f "^$ENGINE" >/dev/null || exit 0; sleep 0.5; done
echo "still running" >&2; exit 1
