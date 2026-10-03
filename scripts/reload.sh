#!/bin/bash
# Hot-reload widgets (UI) and the gadget (game logic) after editing code, no restart.
D="$(dirname "$0")"
"$D/say.sh" "/luaui reload"
"$D/say.sh" "/cheat" "/luarules reload"
