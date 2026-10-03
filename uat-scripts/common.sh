# Shared paths; source this from other scripts.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPTS_DIR")"
BAR_DIR="$(dirname "$(dirname "$MOD_DIR")")"
ENGINE="$BAR_DIR/engine/recoil_2026.07.04/spring"
INFOLOG="$BAR_DIR/infolog.txt"
