#!/usr/bin/env bash
# Start GodotCode in a clean project.
# Usage: ./start_godotcode.sh [project_path]
set -euo pipefail

GODOT="C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe"
PLUGIN_SOURCE="$(cd "$(dirname "$0")" && pwd)/addons/godotcode"
PROJECT="${1:-C:/Users/aaron/godotcode-sandbox}"

# Create project if it doesn't exist
if [ ! -f "$PROJECT/project.godot" ]; then
	mkdir -p "$PROJECT/addons"
	cp -r "$PLUGIN_SOURCE" "$PROJECT/addons/godotcode"
	cat > "$PROJECT/project.godot" << 'GODOTCFG'
; Engine configuration file.
config_version=5

[application]

config/name="GodotCode"
config/features=PackedStringArray("4.6")

[editor_plugins]

enabled=PackedStringArray("res://addons/godotcode/plugin.cfg")
GODOTCFG
	echo "Created fresh project at $PROJECT"
fi

exec "$GODOT" --editor --path "$PROJECT"
