# claude-rings: CLAUDE_CONFIG_DIR로 claude를 실행하는 동안 사용량 위젯을 띄운다.
# 사용법: claude_rings_run <config-dir> [claude 인자...]
claude_rings_run() {
  local cfg="$1"; shift
  local dir="$HOME/.claude-rings/sessions"
  mkdir -p "$dir" && print -r -- "$cfg" > "$dir/$$"
  pgrep -x ClaudeRings >/dev/null || open -g "$HOME/Applications/ClaudeRings.app"
  # claude가 인터럽트(Ctrl-C)로 죽어도 세션 파일이 남지 않도록 always 블록에서 정리한다.
  # always 블록이 자체적으로 실패하지 않는 한 종료 코드는 try 블록의 것을 그대로 따른다.
  {
    CLAUDE_CONFIG_DIR="$cfg" command claude "$@"
  } always {
    rm -f "$dir/$$"
  }
}
