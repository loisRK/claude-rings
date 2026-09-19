# claude-rings: CLAUDE_CONFIG_DIR로 claude를 실행하는 동안 사용량 위젯을 띄운다.
# 사용법: claude_rings_run <config-dir> [claude 인자...]
claude_rings_run() {
  local cfg="$1"; shift
  local dir="$HOME/.claude-rings/sessions"
  mkdir -p "$dir" && print -r -- "$cfg" > "$dir/$$"
  pgrep -x ClaudeRings >/dev/null || open -g "$HOME/Applications/ClaudeRings.app"
  CLAUDE_CONFIG_DIR="$cfg" command claude "$@"
  local rc=$?
  rm -f "$dir/$$"
  return $rc
}
