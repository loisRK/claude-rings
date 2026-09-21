# claude-rings

여러 Claude Code 계정의 **플랜 사용량(Session·Weekly 잔여율)** 을 화면 위에 떠 있는 작은 Liquid Glass 링으로 보여주는 macOS 위젯입니다.

> 🚧 개발 중 — 설계는 [docs/DESIGN.md](docs/DESIGN.md)를 참고하세요.

## 왜 만들었나

`CLAUDE_CONFIG_DIR`로 계정을 나눠 쓰면(예: `alias claude-****='CLAUDE_CONFIG_DIR=~/.claude/**** claude'`) Claude Code는 계정별 인증 정보를 별도의 Keychain 항목(`Claude Code-credentials-<해시>`)에 저장합니다. 기존 사용량 모니터링 앱은 기본 계정만 읽기 때문에 나머지 계정의 한도를 볼 수 없습니다.

claude-rings는 설정한 **모든 config 디렉터리**의 사용량을 조회해 계정별 링으로 보여줍니다.

```text
   ◎ 76      ◎ 100
     80         97
    main      ****•
```

- 바깥 링: Session(5시간) 잔여율
- 안쪽 링: Weekly(주간) 잔여율
- 초록 ≥ 50% · 노랑 ≥ 20% · 빨강 < 20% · 회색 = 만료/미로그인

## 요구 사항

- macOS 26 이상 (Liquid Glass)
- Swift 6 툴체인 (Xcode 또는 Command Line Tools)
- Claude Code에 OAuth(Pro/Max 구독)로 로그인한 계정

## 설치 · 사용법

1. 빌드 및 설치

   ```bash
   git clone https://github.com/loisRK/claude-rings.git
   cd claude-rings
   scripts/build-app.sh --install   # ~/Applications/ClaudeRings.app
   ```

2. 계정 등록 — 최초 실행 시 `~/.config/claude-rings/accounts.json`이 생성됩니다. 추가 계정을 넣으세요.

   ```json
   {
     "accounts": [
       { "name": "main", "configDir": "~/.claude" },
       { "name": "work", "configDir": "~/.claude/work" }
     ],
     "pollIntervalSeconds": 180
   }
   ```

3. 셸 함수 연결 — `~/.zshrc`에 추가합니다.

   ```zsh
   source /path/to/claude-rings/scripts/claude-rings.zsh
   claude-work() { claude_rings_run ~/.claude/work "$@"; }
   ```

   `claude-work`를 실행하면 위젯이 뜨고, 이 함수로 실행한 세션이 모두 끝나면 위젯도 닫힙니다.

4. 위젯 조작 — 드래그로 이동, 마우스를 올리면 리셋 시각 표시, 우클릭으로 새로고침·위치 초기화·설정 열기·종료

## 보안

- Keychain의 토큰은 **읽기만** 하며 갱신하거나 쓰지 않습니다.
- 토큰은 메모리에 캐싱하지 않고, 로그에도 남기지 않습니다.
- 사용량 API 요청은 디스크 캐시·쿠키를 쓰지 않는 ephemeral `URLSession`으로 보내므로, 토큰이 담긴 HTTP 응답이 디스크에 남지 않습니다.
- 최근 성공한 사용량 수치(토큰 아님)는 `~/Library/Caches/claude-rings/last-usage.json`에 캐시되며, 재시작 후 새로 조회할 때까지 연하게 표시됩니다.
- macOS가 Keychain 접근을 물으면 **항상 허용**을 선택하세요.

## 참고

사용량 조회에 쓰는 `api/oauth/usage` 엔드포인트는 Anthropic의 비공식 API입니다. 예고 없이 바뀔 수 있습니다.

## License

[MIT](LICENSE)
