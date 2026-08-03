#!/usr/bin/env bash
# Launch XSpaceWar-AI from any working directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    printf 'Error: Godot was not found. Run ./install.sh first, or set GODOT to its path.\n' >&2
    exit 127
fi

exec "$GODOT" --path "$ROOT" "$@"
