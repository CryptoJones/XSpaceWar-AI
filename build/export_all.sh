#!/usr/bin/env bash
# Export release builds for all platforms locally.
# Requires the Godot 4.6.3 export templates to be installed
# (Editor -> Manage Export Templates, or unzip the .tpz into
#  ~/.local/share/godot/export_templates/4.6.3.stable/).
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
mkdir -p build/out/linux build/out/windows build/out/macos

"$GODOT" --headless --path . --import || true
for preset in Linux Windows macOS; do
    echo "=== Exporting $preset ==="
    "$GODOT" --headless --path . --export-release "$preset"
done

echo "Done:"
find build/out -type f -newer project.godot | sed 's/^/  /'
