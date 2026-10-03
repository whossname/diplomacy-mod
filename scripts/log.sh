#!/bin/bash
# Follow the engine log, filtered to diplomacy lines and Lua errors. Use "all" for everything.
. "$(dirname "$0")/common.sh"
if [ "$1" = all ]; then tail -n 50 -F "$INFOLOG"
else tail -n 200 -F "$INFOLOG" | grep --line-buffered -i -E "diplo|Error|Removed widget|Removed gadget|attempt to"; fi
