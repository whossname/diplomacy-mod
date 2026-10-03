#!/bin/bash
# Send chat/slash command(s) to the running game, e.g.: say.sh "/diplo info"
. "$(dirname "$0")/common.sh"
for line in "$@"; do python3 "$SCRIPTS_DIR/say.py" "$line"; sleep 0.4; done
