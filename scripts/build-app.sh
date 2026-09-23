#!/usr/bin/env bash
# 릴리스 빌드 후 build/ClaudeRings.app을 만든다. --install이면 ~/Applications에 복사한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClaudeRings
bin_dir="$(swift build -c release --show-bin-path)"

app="build/ClaudeRings.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ClaudeRings" "$app/Contents/MacOS/ClaudeRings"
cp Support/Info.plist "$app/Contents/Info.plist"
# SwiftPM 리소스 번들(로고 에셋 등)을 Bundle.module이 찾는 Contents/Resources로 복사한다.
if [[ -d "$bin_dir/ClaudeRings_ClaudeRings.bundle" ]]; then
  cp -R "$bin_dir/ClaudeRings_ClaudeRings.bundle" "$app/Contents/Resources/"
fi
codesign --force --sign - "$app"
# --install이면 아래에서 중간 산출물을 지우므로, 남지 않을 경로를 알리지 않는다.
[[ "${1:-}" == "--install" ]] || echo "built: $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ClaudeRings.app"
  cp -R "$app" "$HOME/Applications/"
  echo "installed: $HOME/Applications/ClaudeRings.app"
  # 중간 산출물을 남기면 Spotlight가 설치본과 함께 두 개로 잡아 헷갈린다.
  rm -rf "$app"
fi
