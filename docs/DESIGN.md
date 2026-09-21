# claude-rings 설계 문서

> 작성일: 2026-09-18 · 상태: 설계 확정, 구현 전

## 1. 배경과 목표

### 문제
Claude Code를 여러 계정으로 쓰기 위해 `CLAUDE_CONFIG_DIR`로 config 디렉터리를 나눠 쓰는 경우가 있습니다.

```bash
alias claude-****='CLAUDE_CONFIG_DIR=~/.claude/**** claude'
```

Claude Code는 config 디렉터리마다 OAuth 인증 정보를 **별도의 macOS Keychain 항목**에 저장합니다. 그런데 기존 사용량 모니터링 앱은 기본 항목(`Claude Code-credentials`)만 읽습니다. 그래서 alias로 분리한 계정의 사용량은 추적되지 않습니다.

### 목표
- 등록한 **모든 계정**의 플랜 한도(Session 5시간 / Weekly 주간) 잔여율을 한눈에 봅니다.
- 판단 기준은 "지금 이 계정을 써도 되는가, 다른 계정으로 갈아타야 하는가"입니다.
- 항상 실행되는 **메뉴바 앱**으로, 상태 항목 하나에 계정별 요약을 보여주고 클릭하면
  Liquid Glass 팝오버로 자세히 봅니다(과거의 "항상 위에 뜨는 떠 있는 패널" 방식은
  마우스가 닿지 않는 영역이 생기고 다른 창에 가려지는 문제가 있어 폐기했습니다).

### 범위 밖(Non-goals)
- 토큰·비용 통계(일별 사용량, 모델별 비용 등)
- 토큰 갱신(refresh) 및 Keychain 쓰기 — 위젯은 **읽기 전용**입니다.
- macOS 외 플랫폼

## 2. 핵심 기술 사실

| 항목 | 내용 |
|---|---|
| Keychain 서비스명 | 기본 config(`~/.claude`)는 `Claude Code-credentials`입니다. `CLAUDE_CONFIG_DIR` 지정 시에는 `Claude Code-credentials-<sha256(절대경로)의 앞 8자리 hex>`입니다. |
| 검증 예시 | `sha256("/Users/alice/.claude/work")[0..8] = 4163034c` → `Claude Code-credentials-4163034c` |
| Keychain 읽기 방식 | Security.framework 대신 `/usr/bin/security` CLI를 씁니다. Claude Code가 저장한 항목은 `security` 도구에 대한 접근 허용이 이미 걸려 있을 가능성이 높아서, 허용 창이 뜨지 않습니다. 앱을 다시 빌드해 서명이 바뀌어도 허용을 다시 묻지 않습니다. (구현 1단계에서 검증) |
| 주의 | 경로 끝에 `/`가 붙으면 해시가 달라집니다. 경로는 틸드(`~`)를 확장하고 끝의 `/`를 제거해 정규화합니다. |
| 사용량 API | `GET https://api.anthropic.com/api/oauth/usage`, 헤더 `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20` |
| API 상태 | **비공식 엔드포인트**입니다. 구현 1단계에서 실제 응답 스키마를 검증하고, 스키마가 바뀌어도 앱이 죽지 않도록 방어적으로 파싱합니다. |

## 3. 아키텍처

```text
┌──────── zsh: claude_rings_run() ───────────┐
│ 1. 세션 파일 등록  ~/.claude-rings/sessions/<셸 PID> (내용: config 경로) │
│ 2. 앱 미실행 시 open -g ClaudeRings.app        │
│ 3. CLAUDE_CONFIG_DIR=<config 경로> claude      │
│ 4. claude 종료 시 세션 파일 삭제                 │
└────────────────────────────────────────────┘
                      │
                      ▼
┌───────────────────── ClaudeRings.app(항상 실행) ─────────────────────┐
│ AccountStore ──► 계정 목록(name, configDir, service)                   │
│      │                                                                │
│      ▼  (3분 주기, 계정별 — service로 ServiceRegistry에서 조합을 고름)     │
│ ServiceRegistry ─► (TokenProvider, UsageFetching) ─► AccountPoller ─► API │
│                                        │                              │
│                                        ▼                              │
│                              UsageViewModel(상태)                      │
│                                        │                              │
│                                        ▼                              │
│                  MenuBarController(NSStatusItem 1개 + NSPopover)       │
│                     · 상태 항목: 계정별 [로고 게이지][Session %/Weekly %] │
│                     · 팝오버: 계정별 상세 + 색상 설정 + 로그인 시 자동 실행 │
│                                                                        │
│ SessionWatcher ──► 활성 계정(●) 표시만, 앱 종료는 하지 않음                │
└────────────────────────────────────────────────────────────────────────┘
```

### 구성 요소

| 모듈 | 책임 | 의존 |
|---|---|---|
| `AccountStore` | `~/.config/claude-rings/accounts.json` 로드. 파일이 없으면 기본값(main=`~/.claude` 하나)으로 생성하고, 추가 계정은 사용자가 직접 등록 | 파일 시스템 |
| `ServiceID` / `ServiceRegistry` | 계정의 `service`에 맞는 `TokenProvider`·`UsageFetching` 조합을 고름. 미등록 서비스는 nil(호출부가 "지원하지 않는 서비스"로 표시) | — |
| `KeychainService` / `KeychainTokenProvider` | config dir → 서비스명 변환, `/usr/bin/security find-generic-password -s <서비스명> -w`로 credentials JSON을 읽어 `claudeAiOauth.accessToken` 추출(Claude 서비스 구현) | `/usr/bin/security` |
| `UsageClient` | Claude 사용량 API 호출 → `Usage` 모델(Session·Weekly 사용률, 리셋 시각) 반환(Claude 서비스 구현) | URLSession |
| `AccountPoller` | 토큰 읽기 → 조회 → 401 시 1회 재시도 → 다음 상태 결정 | 위 2개 |
| `UsageViewModel` | 계정별 조회 루프, 백오프, 화면 상태 보관 | `ServiceRegistry` |
| `SessionWatcher` | 세션 디렉터리의 PID 생존 확인(`kill(pid, 0)`), 활성 계정 집합만 만듦(더 이상 앱을 종료하지 않음) | 파일 시스템 |
| `LevelColors`/`RGBAColor` (Core), `ThemeStore` (App) | 여유·주의·경고 3단계 사용자 지정 색을 hex로 저장·복원(`UserDefaults`) | — |
| `MenuBarController` | `NSStatusItem` 1개 + 클릭 시 여는 `NSPopover` 관리 | AppKit, SwiftUI |
| `ServiceGaugeGlyph` | 서비스 로고(또는 `FallbackGlyph`)를 잔여율만큼 채워 보여주는 게이지 | SwiftUI |
| `LoginItemModel` | `SMAppService.mainApp`으로 로그인 시 자동 실행 등록/해제 | ServiceManagement |

각 모듈은 프로토콜 뒤에 두어 테스트에서 가짜 구현(fake)으로 교체할 수 있게 합니다.

### 설정 파일 예시

```json
{
  "accounts": [
    { "name": "main", "service": "claude", "configDir": "~/.claude" },
    { "name": "work", "service": "claude", "configDir": "~/.claude/work" }
  ],
  "pollIntervalSeconds": 180
}
```

`configDir`가 기본 경로(`~/.claude`)이면 해시 접미사가 없는 서비스명을 씁니다. `service`
필드가 없으면 `claude`로 간주하므로 기존 설정 파일도 그대로 동작합니다.

### 서비스 확장

지금은 Claude만 구현돼 있지만, 다른 AI 코딩 서비스(예: Codex, Antigravity)를 나중에
추가할 수 있도록 자리를 마련해 뒀습니다(YAGNI 원칙에 따라 지금은 자리만 만들고 실제
구현은 하지 않습니다). 새 서비스를 추가하려면:

1. **서비스 id**: `ServiceID(rawValue: "codex")`처럼 새 식별자를 정의합니다.
2. **토큰 소스**: 그 서비스의 인증 정보를 읽는 `TokenProvider` 구현을 추가합니다
   (`Sources/ClaudeRingsCore/TokenProvider.swift` 또는 새 파일).
3. **엔드포인트·파서**: 그 서비스의 사용량 API를 호출·해석하는 `UsageFetching` 구현을
   추가합니다(`Sources/ClaudeRingsCore/UsageClient.swift` 또는 새 파일).
4. **레지스트리 등록**: `ServiceRegistry`에 위 둘을 묶어 등록합니다
   (`Sources/ClaudeRingsCore/Service.swift`).
5. **로고 에셋**: `Sources/ClaudeRings/Resources/logos/<service-id>.png`를 추가합니다.
   없으면 중립 대체 도형(`FallbackGlyph`)이 대신 쓰입니다.

`UsageViewModel`·메뉴바·팝오버 등 나머지 코드는 건드릴 필요가 없습니다(계정의
`service` 필드로 자동으로 맞는 조합을 고릅니다).

## 4. 데이터 흐름과 상태

### 조회 주기
- 기본 180초 간격으로 조회합니다. 앱 시작 시에는 즉시 1회 조회합니다.
- **토큰은 캐싱하지 않고 매 조회 때마다 Keychain에서 새로 읽습니다.** 그래서 만료된 계정도 사용자가 그 계정으로 Claude Code를 쓰면(Claude Code가 토큰을 갱신해 Keychain에 저장) 다음 주기에 자동으로 복구됩니다.
- 최근 성공한 사용량 수치(토큰 제외)는 `~/Library/Caches/claude-rings/last-usage.json`에 캐시됩니다. 앱 재시작 후 새 조회가 성공하기 전까지 캐시된 값을 50% 투명도로 `stale` 상태로 표시합니다. 재시작 직후 첫 조회에서 HTTP 429로 차단되면 이전 값이 없을 수 있는데, 이 경우 백오프 재시도(최대 900초)를 기다리는 동안 위젯이 빈 상태로 나타나는 것을 피하기 위해 캐시된 값을 임시로 보여줍니다.

### 계정별 상태

| 상태 | 조건 | 표시 |
|---|---|---|
| `loading` | 최초 조회 전 | 메뉴바 숫자는 "—", 팝오버는 "불러오는 중…" |
| `ok(usage)` | 정상 응답 | 게이지 채움 + 남은 % |
| `stale(usage)` | 429 또는 네트워크 오류, 이전 값 있음 | 이전 값을 50% 투명도로 표시 |
| `expired` | 401 → Keychain 재조회 후 재시도해도 401 | "만료" |
| `missing` | Keychain 항목 없음(미로그인) | "로그인 필요" |
| `error` | 그 외(파싱 실패, 미등록 서비스 등) | "오류"(또는 미등록 서비스면 "지원하지 않는 서비스: `<id>`") |
| 조회 일시 제한(429, retry-after) | 429 응답에 `Retry-After`가 있어 해당 시간까지 재조회하지 않음 | 이전 값 없으면 메뉴바에 clock 아이콘 + 남은 시간(예: "59m"). 이전 값 있으면 흐린 숫자 그대로 표시하고 팝오버에 "조회 일시 제한 · N 후 재시도" |

이 상태는 **Claude 사용 한도 초과가 아니라 사용량 조회 API 자체의 호출 제한**입니다. 사용자가 실제로 계정을 더 쓸 수 없는 상태와 혼동하지 않도록 "!"와 구분해 표시합니다.

### 백오프
- 429나 네트워크 오류가 나면 해당 계정의 조회 간격을 2배씩 늘립니다(최대 15분).
- 성공하면 기본 간격으로 되돌립니다.
- 서버가 `Retry-After`를 지시하면 그 시간(최대 2시간)까지는 조회하지 않습니다. 백오프 간격과 `Retry-After` 중 더 긴 쪽을 따릅니다(`PollSchedule.nextDelay`).

### 표시 값
- **남은 % = 100 − utilization**입니다(기존 상용 앱의 "76% left"와 같은 기준).
- Session(5시간)과 Weekly(주간)는 각각 별도의 게이지입니다(팝오버). 메뉴바의 게이지
  하나는 그중 더 급한(낮은) 잔여율을 기준으로 채웁니다(§6 참고).

## 5. 실행 수명 주기

메뉴바 앱은 **항상 실행**됩니다. 이전에는 세션이 모두 끝나면 앱이 스스로 종료했지만,
메뉴바 앱은 늘 같은 자리에 있는 게 목적이라 더 이상 그렇게 하지 않습니다.

### 로그인 시 자동 실행
- `SMAppService.mainApp.register()` / `.unregister()`로 등록·해제합니다. 상태는
  `SMAppService.mainApp.status`로 읽습니다(팝오버의 체크박스가 이 값을 반영).
- `SMAppService`는 실제 코드사인된 `.app` 번들이 있어야 동작하므로 `swift run`으로
  실행할 때는 등록이 실패할 수 있습니다. 실패해도 앱이 죽지 않고 팝오버에 오류
  메시지를 보여줍니다(`LoginItemModel.lastError`).

### 셸 함수(`scripts/claude-rings.zsh`, `~/.zshrc`의 alias를 대체)

```zsh
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

# 계정별 래퍼 예시
claude-work() { claude_rings_run ~/.claude/work "$@"; }
```

- 세션 파일 이름은 claude를 실행한 **대화형 셸의 PID**(`$$`)이고, 내용은 **config 디렉터리 경로**입니다. 앱은 이 내용으로 "지금 실행 중인 계정"을 강조 표시(●)합니다.
- 터미널 탭마다 셸 PID가 다르므로 여러 세션을 동시에 추적할 수 있습니다.
- 터미널을 강제로 닫아도 셸 PID가 사라지므로 `SessionWatcher`가 정리합니다.
- `pgrep -x ClaudeRings >/dev/null || open -g ...`는 로그인 시 자동 실행을 꺼둔
  사용자를 위해 그대로 남겨 뒀습니다. 앱이 이미 떠 있으면 아무 일도 하지 않습니다.

### SessionWatcher
- 5초마다 세션 디렉터리의 파일명(PID)을 `kill(pid, 0)`으로 확인합니다.
- 죽은 PID의 파일은 삭제하고, 살아 있는 파일의 내용(config 경로)을 모아 활성 계정 목록을 만듭니다.
- **더 이상 이 정보로 앱을 종료하지 않습니다.** `shouldQuit` 판단 로직 자체는 Core에
  남아 있고 테스트도 그대로지만, 앱 계층(`AppDelegate`)이 그 값을 더 이상 쓰지 않고
  활성 계정 표시(●)에만 씁니다.

## 6. UI — 메뉴바 + 팝오버

### 메뉴바 항목(`NSStatusItem`)
- `NSStatusBar.system.statusItem(withLength: .variableLength)` **1개**만 씁니다. 계정
  수만큼 항목을 만들지 않습니다.
- 콘텐츠는 `NSHostingView`로 `statusItem.button` 안에 **실시간으로** 얹습니다. 처음에는
  `ImageRenderer`로 스냅샷을 구워 넣는 방식을 썼지만, 그러면 시스템 다크/라이트 모드가
  바뀌어도 이미 구운 이미지는 따라가지 못한다는 문제가 검증 중 발견돼 라이브 호스팅으로
  되돌렸습니다. `UsageViewModel`·`ThemeStore` 모두 `@Observable`이라 값이 바뀌면 이
  서브뷰가 자동으로 다시 그려집니다.
- 텍스트는 항상 `.foregroundStyle(.primary)`만 쓰고 검정/흰색을 직접 지정하지
  않습니다. 메뉴바의 실제 다크/라이트 상태(배경 벽지·시스템 설정에 따라 결정)를
  그대로 따라가야 하기 때문입니다.
- `.variableLength`는 버튼 안 커스텀 SwiftUI 서브뷰의 폭을 자동으로 반영하지
  않으므로, 콘텐츠 뷰가 `.onGeometryChange`로 실제 너비를 계속 알려주고 그 값을
  `statusItem.length`에 반영합니다. 계정 목록 자체는 시작 시 1회만 로드돼 바뀌지
  않지만, 표시되는 **텍스트**는 실행 중 바뀝니다(첫 값이 오기 전 `—`, 조회 일시
  제한 중이면 시계 아이콘+남은 시간으로 바뀌는 등) — 그래서 폭도 한 번이 아니라
  계속 갱신해야 합니다.

```text
메뉴바:   ✳ 76%   ✳ 97%          ← 계정별로 [로고 게이지][Session %]
             80%      92%          두 번째 줄은 Weekly %
```

- 게이지 색·채움 비율은 Session·Weekly 중 **더 낮은 쪽**(min)을 기준으로 합니다. 두
  한도 중 어느 쪽이든 먼저 닥치는 쪽이 실제 위험이기 때문입니다(숫자 두 줄 자체는
  각자의 값 그대로).
- 값이 없으면 `—`, 조회 일시 제한 중이면 clock 아이콘(`Image(systemName: "clock")`) +
  남은 시간(예: "59m")으로 대체합니다.
- `stale`(이전 값 유지 중)이면 투명도 0.5로 낮춥니다.
- Dock 아이콘은 없습니다(`LSUIElement = true`).

### 게이지(`ServiceGaugeGlyph`)
- 계정의 서비스 로고(`Resources/logos/<service-id>.png`, 없으면 중립 대체 도형
  `FallbackGlyph`)를 잔여율만큼 **아래에서 위로** 채워 보여주는 게이지입니다.
- 구현은 경로를 다시 그리지 않고 **마스킹**으로 합니다: 전체 도형을 낮은 투명도
  (0.18)의 단계 색으로 깔고, 그 위에 잔여율 비율만큼의 사각형으로 마스킹한 완전한
  색을 겹칩니다. 값이 바뀌면 스프링 애니메이션을 적용합니다.
- 값이 없으면 도형을 낮은 투명도의 중립색으로만 보여줍니다(채움 없음).
- 단계 색(여유/주의/경고)은 사용자가 팝오버에서 바꿀 수 있습니다(§ 색상 설정).

### 팝오버(`NSPopover`)
- 메뉴바 항목을 클릭하면 열고(`behavior = .semitransient`), 다시 클릭하거나 바깥을
  누르면 닫힙니다. `.semitransient`인 이유는 색상 설정의 `ColorPicker`가 여는
  `NSColorPanel` 같은 보조 창이 키 윈도우가 돼도 팝오버가 바깥 클릭으로 오인해
  닫히지 않게 하기 위해서입니다(`.transient`였다면 그 순간 닫혀 색 편집이 끊깁니다).
- 계정마다 세로로 나열:
  - 계정 이름, 실행 중이면 ● 표시
  - Session·Weekly 게이지 두 개를 나란히(각자의 잔여율로 채움·색 결정), 옆에 퍼센트와
    "N 후 리셋"
  - 만료·로그인 필요·오류·조회 일시 제한 상태도 그대로 표시
  - 등록되지 않은 서비스를 쓰는 계정은 "지원하지 않는 서비스: `<id>`"로 표시
- Liquid Glass는 팝오버 안에서 계속 씁니다: 계정별 카드가
  `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))`.

```text
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

### 색상 설정
- 여유(≥50%)·주의(≥20%)·경고(<20%) 3단계 색을 `ColorPicker` 3개로 바꿀 수 있습니다.
  "기본값으로" 버튼으로 초기 색(초록/노랑/빨강)으로 되돌립니다.
- `UserDefaults`에 hex 문자열로 저장하고(`ThemeStore`), 앱 시작 시 불러오며, 바꾸는
  즉시 메뉴바·팝오버 양쪽에 반영됩니다.
- 순수 로직(hex ↔ RGBA 변환, 잔여율 → 단계 색 선택)은 Core(`Theme.swift`)에 있고
  SwiftUI `Color`는 App 계층에서만 씁니다.

### 로그인 시 자동 실행
- 팝오버의 체크박스가 `SMAppService.mainApp.status`를 반영하고, 토글하면
  `register()`/`unregister()`를 호출합니다.

### 다크/라이트 모드
- 게이지의 단계 색은 사용자가 고른 고정 색입니다.
- 그 외 텍스트·중립 UI는 전부 시스템 라벨 색(`.primary`)을 써서 메뉴바·팝오버의
  실제 다크/라이트 상태를 자동으로 따라갑니다.

## 7. 오류 처리

| 상황 | 처리 |
|---|---|
| 401 Unauthorized | Keychain을 다시 읽어 1회 재시도하고, 실패하면 `expired`로 표시 |
| 429 Too Many Requests | 이전 값을 유지(`stale`, 없으면 `error`)하고 백오프. `Retry-After` 헤더가 있으면 그 시간(최대 2시간)까지 조회하지 않고, 메뉴바에 "조회 일시 제한"(clock 아이콘 + 남은 시간)을 표시함. **Claude 사용 한도 초과가 아니라 사용량 조회 API의 호출 제한**임을 구분해 보여줌 |
| 네트워크 오류·타임아웃(10초) | 이전 값을 유지(`stale`)하고 백오프 |
| 응답 스키마 불일치 | 필드별 옵셔널 파싱. 없는 필드는 "—"로 표시 |
| Keychain 접근 거부 | `missing`으로 표시. macOS 허용 창이 뜨면 "항상 허용"을 선택하도록 README에 안내 |
| 설정 파일 손상 | 기본값으로 동작하고 로그 기록 |

토큰 값은 로그·오류 메시지에 절대 출력하지 않습니다.

## 8. 프로젝트 구조

```text
claude-rings/
├── Package.swift                   # Swift Package (macOS 26+), ClaudeRings 리소스 포함
├── Sources/
│   ├── ClaudeRingsCore/            # UI와 무관한 로직 (테스트 대상)
│   │   ├── Account.swift           # Account(service 포함), AppConfig, AccountStore
│   │   ├── Service.swift           # ServiceID, ServiceRegistry
│   │   ├── Theme.swift             # RGBAColor, LevelColors(hex 직렬화, 단계 색 선택)
│   │   ├── KeychainService.swift   # 경로 정규화, 서비스명 변환
│   │   ├── TokenProvider.swift     # security CLI로 토큰 읽기(Claude)
│   │   ├── Usage.swift             # Usage 모델, 응답 파싱
│   │   ├── UsageClient.swift       # API 요청, 상태 코드 해석(Claude)
│   │   ├── UsageState.swift        # 상태, 색상 단계, 백오프, 리셋 시간 표기
│   │   ├── AccountPoller.swift     # 토큰 읽기 → 조회 → 401 재시도 → 상태 결정
│   │   └── SessionWatcher.swift    # 세션 PID 추적, 활성 계정 판단
│   └── ClaudeRings/                # 앱 실행 파일
│       ├── main.swift              # NSApplication 설정
│       ├── AppDelegate.swift       # 조립, 세션 타이머
│       ├── UsageViewModel.swift    # 계정별 조회 루프(ServiceRegistry 사용)
│       ├── ThemeStore.swift        # 사용자 지정 색 저장·복원, Color↔RGBAColor 변환
│       ├── LoginItemModel.swift    # SMAppService 래핑
│       ├── MenuBarController.swift # NSStatusItem + NSPopover
│       ├── MenuBarContentView.swift # 메뉴바 항목 SwiftUI 콘텐츠
│       ├── PopoverView.swift       # 팝오버 SwiftUI 콘텐츠 + Liquid Glass
│       ├── ServiceGaugeGlyph.swift # 로고를 잔여율만큼 채우는 게이지, 로고 조회
│       ├── FallbackGlyph.swift     # 로고 없는 서비스용 중립 대체 도형
│       └── Resources/logos/        # 서비스별 로고 PNG(`<service-id>.png`)
├── Tests/ClaudeRingsCoreTests/
├── Support/Info.plist              # .app 번들용 (LSUIElement)
├── scripts/
│   ├── probe-usage.sh              # 사용량 API 수동 확인 (토큰 비출력)
│   ├── build-app.sh                # swift build → .app 번들(+리소스) → ~/Applications 설치
│   └── claude-rings.zsh            # 셸 함수
├── docs/DESIGN.md
├── docs/PLAN.md
└── README.md
```

## 9. 테스트 전략

Swift Testing(`import Testing`)으로 `ClaudeRingsCore`를 단위 테스트합니다.

| 대상 | 방법 |
|---|---|
| 서비스명 변환 | 기본 경로, 틸드 확장, 끝 `/` 제거, 알려진 해시(`/Users/alice/.claude/work` → `4163034c`) 검증 |
| 응답 파싱 | 샘플 JSON 픽스처(정상, 필드 누락, null) |
| 남은 %·색상 | 경계값(0, 20, 50, 100) |
| 백오프 | 연속 실패 시 간격 2배, 상한, 성공 시 초기화 |
| SessionWatcher | 가짜 PID 검사기로 생존·종료·유예 시간 확인 |
| UI | 수동 확인(라이트/다크 모드에서 메뉴바 항목·팝오버가 읽히는지) |

## 10. 구현 순서

1. **API 검증**: 실제 사용량 API 응답을 확인하고 샘플을 픽스처로 저장(토큰은 마스킹)
2. Core 모듈을 TDD로 구현
3. 메뉴바 항목 + 팝오버(Liquid Glass) UI
4. 빌드 스크립트와 `.app` 번들
5. 셸 함수 적용(`~/.zshrc` 수정은 사용자 확인 후)
