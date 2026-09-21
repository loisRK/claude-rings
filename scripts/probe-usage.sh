#!/usr/bin/env bash
# 사용량 API 응답을 확인한다. 토큰은 출력하지 않는다.
# 사용법: scripts/probe-usage.sh [config-dir]   (기본값: ~/.claude)
set -euo pipefail

cfg="${1:-$HOME/.claude}"
cfg="${cfg/#\~/$HOME}"
cfg="${cfg%/}"

if [[ "$cfg" == "$HOME/.claude" ]]; then
  svc="Claude Code-credentials"
else
  svc="Claude Code-credentials-$(printf '%s' "$cfg" | shasum -a 256 | cut -c1-8)"
fi
echo "keychain service: $svc" >&2

token="$(security find-generic-password -s "$svc" -w \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')"

# 토큰이 프로세스 인자에 노출되지 않도록 헤더를 stdin으로 전달한다.
printf 'Authorization: Bearer %s\n' "$token" | curl -sS -w '\nHTTP %{http_code}\n' \
  -H @- \
  -H 'anthropic-beta: oauth-2025-04-20' \
  -H 'Accept: application/json' \
  https://api.anthropic.com/api/oauth/usage
