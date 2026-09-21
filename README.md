# claude-rings

여러 Claude Code 계정의 **플랜 사용량(Session·Weekly 잔여율)** 을 메뉴바에서 바로 보여주는
macOS 앱입니다. 설계는 [docs/DESIGN.md](docs/DESIGN.md)를 참고하세요.

## 상표

이 프로젝트는 **Anthropic과 무관한 비공식 도구**입니다. "Claude"와 Claude 로고는
Anthropic의 상표이며, 이 앱에서는 계정별 잔여율 게이지를 그리는 용도로만 씁니다
(자세한 출처는 [Sources/ClaudeRings/Resources/README.md](Sources/ClaudeRings/Resources/README.md) 참고).

## 왜 만들었나

`CLAUDE_CONFIG_DIR`로 계정을 나눠 쓰면(예: `alias claude-****='CLAUDE_CONFIG_DIR=~/.claude/**** claude'`) Claude Code는 계정별 인증 정보를 별도의 Keychain 항목(`Claude Code-credentials-<해시>`)에 저장합니다. 기존 사용량 모니터링 앱은 기본 계정만 읽기 때문에 나머지 계정의 한도를 볼 수 없습니다.

claude-rings는 설정한 **모든 config 디렉터리**의 사용량을 조회해 메뉴바 항목 하나에
계정별로 보여줍니다.

```text
메뉴바:   ✳ 76%   ✳ 97%          ← 계정별 [로고 게이지][Session %]
             80%      92%          두 번째 줄은 Weekly %
                 ↓ 클릭
   ┌──────────────────────────────────┐
   │  main                             │
   │   ✳76  Session 76%   2h 51m 후 리셋 │
   │   ✳80  Weekly  80%   1d 15h 후 리셋 │
   │  ──────────────────────────────── │
   │  색상                     기본값으로 │
   │  여유 🟩  주의 🟨  경고 🟥            │
   │  ──────────────────────────────── │
   │  ☐ 로그인 시 자동 실행               │
   │  새로고침   설정 열기          종료   │
   └──────────────────────────────────┘
```

- 게이지는 잔여율만큼 아래에서 위로 채워집니다.
- 여유 ≥ 50% · 주의 ≥ 20% · 경고 < 20% — 세 색 모두 팝오버에서 직접 바꿀 수 있습니다.
- 메뉴바 게이지 하나는 Session·Weekly 중 더 급한(낮은) 쪽을 기준으로 채워지고, 팝오버는
  둘을 각각 따로 보여줍니다.

## 요구 사항

- macOS 26 이상 (Liquid Glass)
- Swift 6.2 (Xcode 26)
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
       { "name": "main", "service": "claude", "configDir": "~/.claude" },
       { "name": "work", "service": "claude", "configDir": "~/.claude/work" }
     ],
     "pollIntervalSeconds": 180
   }
   ```

   `service` 필드는 생략하면 `claude`로 간주합니다(지금은 Claude만 지원하며, 다른 AI
   코딩 서비스는 나중에 추가될 수 있도록 자리만 마련해 뒀습니다 — `docs/DESIGN.md`의
   "서비스 확장" 참고).

3. 셸 함수 연결 — `~/.zshrc`에 추가합니다.

   ```zsh
   source /path/to/claude-rings/scripts/claude-rings.zsh
   claude-work() { claude_rings_run ~/.claude/work "$@"; }
   ```

   `claude-work`를 실행하면 앱이 아직 안 떠 있을 때만 자동으로 실행됩니다(로그인 시
   자동 실행을 켜 두면 보통 이미 떠 있을 것입니다). **기존에 같은 이름으로 등록해 둔
   `alias claude-work=...`가 있다면 먼저 지우세요.** zsh는 같은 이름의 alias와 함수가
   둘 다 있으면 alias가 우선하므로, 지우지 않으면 위 함수가 아니라 예전 alias가 계속
   실행되어 세션이 추적되지 않습니다.

4. 메뉴바 조작 — 클릭하면 팝오버가 열립니다. 팝오버에서 새로고침·설정 파일 열기·
   로그인 시 자동 실행 토글·종료·색상 설정을 할 수 있습니다.

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
