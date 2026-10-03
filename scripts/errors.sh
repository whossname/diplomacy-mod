#!/bin/bash
# One-shot: show Lua errors / removed widgets from the last run.
. "$(dirname "$0")/common.sh"
grep -n -E "Error (in|:)|Removed (widget|gadget)|attempt to" "$INFOLOG" | grep -v "AdvSky\|_dead" || echo "no errors"
