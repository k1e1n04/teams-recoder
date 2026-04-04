#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/create-dmg.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_app="$tmp_dir/TeamsAutoRecorder.app"
mkdir -p "$fake_app/Contents/MacOS"
cat > "$fake_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>9.8.7</string>
</dict>
</plist>
PLIST
touch "$fake_app/Contents/MacOS/TeamsAutoRecorder"

output_dir="$tmp_dir/out"

"$SCRIPT_PATH" \
  --no-build \
  --app-path "$fake_app" \
  --output-dir "$output_dir" \
  --volume-name "TeamsAutoRecorder" \
  --dmg-name-prefix "TeamsAutoRecorder"

test -f "$output_dir/TeamsAutoRecorder-9.8.7.dmg"

"$SCRIPT_PATH" \
  --no-build \
  --app-path "$fake_app" \
  --version "1.2.3" \
  --output-dir "$output_dir" \
  --volume-name "TeamsAutoRecorder" \
  --dmg-name-prefix "TeamsAutoRecorder"

test -f "$output_dir/TeamsAutoRecorder-1.2.3.dmg"

echo "ok: test-create-dmg"
