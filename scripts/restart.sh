#!/bin/bash
# Full restart: needed for new files / modinfo changes. Prefer reload.sh for code edits.
D="$(dirname "$0")"
"$D/stop.sh" && "$D/run.sh"
