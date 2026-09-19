#!/usr/bin/env bash
# 릴리스 빌드 후 build/ClaudeRings.app을 만든다. --install이면 ~/Applications에 복사한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClaudeRings
bin_dir="$(swift build -c release --show-bin-path)"

app="build/ClaudeRings.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/ClaudeRings" "$app/Contents/MacOS/ClaudeRings"
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "built: $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ClaudeRings.app"
  cp -R "$app" "$HOME/Applications/"
  echo "installed: $HOME/Applications/ClaudeRings.app"
fi
