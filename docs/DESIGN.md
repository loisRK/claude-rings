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
- `claude-****` 실행 중에만 화면 한쪽에 **항상 위에 뜨는 작은 Liquid Glass 위젯**으로 표시합니다.

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
┌──────────────── ClaudeRings.app ────────────────┐
│ AccountStore ──► 계정 목록(name, configDir)          │
│      │                                              │
│      ▼  (3분 주기, 계정별)                             │
│ KeychainTokenProvider ─► token ─► UsageClient ─► API │
│                                        │             │
│                                        ▼             │
│                              UsageViewModel(상태)     │
│                                        │             │
│                                        ▼             │
│                          RingsPanel (NSPanel+SwiftUI) │
│                                                      │
│ SessionWatcher ──► 세션 PID 전부 종료 시 앱 종료         │
└──────────────────────────────────────────────────────┘
```

### 구성 요소

| 모듈 | 책임 | 의존 |
|---|---|---|
| `AccountStore` | `~/.config/claude-rings/accounts.json` 로드. 파일이 없으면 기본값(main=`~/.claude` 하나)으로 생성하고, 추가 계정은 사용자가 직접 등록 | 파일 시스템 |
| `KeychainService` / `KeychainTokenProvider` | config dir → 서비스명 변환, `/usr/bin/security find-generic-password -s <서비스명> -w`로 credentials JSON을 읽어 `claudeAiOauth.accessToken` 추출 | `/usr/bin/security` |
| `UsageClient` | 사용량 API 호출 → `Usage` 모델(Session·Weekly 사용률, 리셋 시각) 반환 | URLSession |
| `AccountPoller` | 토큰 읽기 → 조회 → 401 시 1회 재시도 → 다음 상태 결정 | 위 2개 |
| `UsageViewModel` | 계정별 조회 루프, 백오프, 화면 상태 보관 | `AccountPoller` |
| `SessionWatcher` | 세션 디렉터리의 PID 생존 확인(`kill(pid, 0)`), 전부 종료 시 앱 종료 | 파일 시스템 |
| `RingsPanel` | 항상 위에 뜨는 투명 `NSPanel` + SwiftUI 뷰 | AppKit, SwiftUI |

각 모듈은 프로토콜 뒤에 두어 테스트에서 가짜 구현(fake)으로 교체할 수 있게 합니다.

### 설정 파일 예시

```json
{
  "accounts": [
    { "name": "main", "configDir": "~/.claude" },
    { "name": "****", "configDir": "~/.claude/****" }
  ],
  "pollIntervalSeconds": 180
}
```

`configDir`가 기본 경로(`~/.claude`)이면 해시 접미사가 없는 서비스명을 씁니다.

## 4. 데이터 흐름과 상태

### 조회 주기
- 기본 180초 간격으로 조회합니다. 앱 시작 시에는 즉시 1회 조회합니다.
- **토큰은 캐싱하지 않고 매 조회 때마다 Keychain에서 새로 읽습니다.** 그래서 만료된 계정도 사용자가 그 계정으로 Claude Code를 쓰면(Claude Code가 토큰을 갱신해 Keychain에 저장) 다음 주기에 자동으로 복구됩니다.

### 계정별 상태

| 상태 | 조건 | 표시 |
|---|---|---|
| `loading` | 최초 조회 전 | 링 없이 은은한 펄스 |
| `ok(usage)` | 정상 응답 | 이중 링 + 남은 % |
| `stale(usage)` | 429 또는 네트워크 오류, 이전 값 있음 | 이전 값을 50% 투명도로 표시 |
| `expired` | 401 → Keychain 재조회 후 재시도해도 401 | 회색 링 + "만료" |
| `missing` | Keychain 항목 없음(미로그인) | 회색 점선 링 + "로그인 필요" |
| `error` | 그 외(파싱 실패 등) | 회색 링 + "!" |

### 백오프
- 429나 네트워크 오류가 나면 해당 계정의 조회 간격을 2배씩 늘립니다(최대 15분).
- 성공하면 기본 간격으로 되돌립니다.

### 표시 값
- **남은 % = 100 − utilization**입니다(기존 상용 앱의 "76% left"와 같은 기준).
- 바깥 링은 Session(5시간), 안쪽 링은 Weekly(주간)입니다.

## 5. 실행·종료 수명 주기

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

- 세션 파일 이름은 claude를 실행한 **대화형 셸의 PID**(`$$`)이고, 내용은 **config 디렉터리 경로**입니다. 앱은 이 내용으로 "지금 실행 중인 계정"을 강조 표시합니다.
- 터미널 탭마다 셸 PID가 다르므로 여러 세션을 동시에 추적할 수 있습니다.
- 터미널을 강제로 닫아도 셸 PID가 사라지므로 `SessionWatcher`가 정리합니다.
- `open -g`는 백그라운드로 실행하므로 터미널 포커스를 뺏지 않습니다.

### SessionWatcher
- 5초마다 세션 디렉터리의 파일명(PID)을 `kill(pid, 0)`으로 확인합니다.
- 죽은 PID의 파일은 삭제하고, 살아 있는 파일의 내용(config 경로)을 모아 활성 계정 목록을 만듭니다.
- 남은 파일이 0개인 상태가 10초 이상 지속되면 앱을 종료합니다. 유예 시간을 두는 이유는 연속 실행 중 잠깐 비는 순간에 앱이 꺼졌다 켜지는 것을 막기 위해서입니다.
- 디버그용으로 `--standalone` 인자를 주면 세션과 무관하게 계속 실행합니다.

## 6. UI — Liquid Glass

Apple의 Liquid Glass 디자인 언어(macOS 26+ / iOS 26+의 `glassEffect`)를 따릅니다.

### 창(Window)
- `NSPanel`: `styleMask = [.borderless, .nonactivatingPanel]`
- `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` → 모든 데스크톱과 전체 화면 앱 위에 표시됩니다.
- `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false` → 창 자체는 보이지 않고 유리 요소만 떠 있습니다.
- `isMovableByWindowBackground = true` → 드래그로 이동합니다. 위치는 `UserDefaults`에 저장합니다.
- 기본 위치는 메인 화면 우상단(메뉴바 아래 12pt, 오른쪽 여백 16pt)입니다.
- Dock 아이콘은 없습니다(`LSUIElement = true`).

### 레이아웃

```text
   ╭──────╮  ╭──────╮
   │ ◎ 76 │  │ ◎100 │      ← 계정별 원형 유리 버블 (지름 64pt)
   │   80 │  │   97 │         바깥 링 = Session, 안쪽 링 = Weekly
   ╰──────╯  ╰──────╯         중앙 숫자: 위 Session %, 아래 Weekly %
     main      ****•        ← 계정 이름 (실행 중인 계정은 • 강조)
```

### 유리 효과
- 버블들을 `GlassEffectContainer(spacing:)`로 묶습니다. 가까이 붙은 버블은 유리가 서로 녹아드는 효과를 냅니다.
- 각 버블: `.glassEffect(.regular.interactive(), in: .circle)`
- 호버 시 해당 버블이 캡슐 형태로 늘어나며 리셋 시각을 보여줍니다(`glassEffectID` + `@Namespace`로 모핑 애니메이션).

```text
   ╭────────────────────────────╮
   │ ◎ 76  Session  2h 51m 후 리셋 │   ← 호버 시 확장
   │   80  Weekly   1d 15h 후 리셋 │
   ╰────────────────────────────╯
```

### 링
- 두께 5pt, 끝은 둥글게(`lineCap: .round`)
- 트랙(배경 링)은 흰색 15% 투명도라 유리 위에서 은은하게 보입니다.
- 진행 링은 상태 색상의 각도 그라데이션(`AngularGradient`)입니다. 값이 바뀌면 스프링 애니메이션을 적용합니다.

| 남은 % | 색상 |
|---|---|
| 50 이상 | 초록 (`.green`) |
| 20 이상 50 미만 | 노랑 (`.yellow`) |
| 20 미만 | 빨강 (`.red`) |
| 만료·오류·미로그인 | 회색 (`.secondary`) |

- 숫자는 `.monospacedDigit()`과 SF Pro Rounded를 쓰고, 값 변경 시 `.contentTransition(.numericText())`를 적용합니다.
- 다크/라이트 모드는 시스템 설정을 따릅니다. Liquid Glass가 자동으로 적응합니다.

### 우클릭 메뉴
- 지금 새로고침
- 위치 초기화
- 설정 파일 열기
- 종료

## 7. 오류 처리

| 상황 | 처리 |
|---|---|
| 401 Unauthorized | Keychain을 다시 읽어 1회 재시도하고, 실패하면 `expired`로 표시 |
| 429 Too Many Requests | 이전 값을 유지(`stale`)하고 백오프 |
| 네트워크 오류·타임아웃(10초) | 이전 값을 유지(`stale`)하고 백오프 |
| 응답 스키마 불일치 | 필드별 옵셔널 파싱. 없는 필드는 "—"로 표시 |
| Keychain 접근 거부 | `missing`으로 표시. macOS 허용 창이 뜨면 "항상 허용"을 선택하도록 README에 안내 |
| 설정 파일 손상 | 기본값으로 동작하고 로그 기록 |

토큰 값은 로그·오류 메시지에 절대 출력하지 않습니다.

## 8. 프로젝트 구조

```text
claude-rings/
├── Package.swift                   # Swift Package (macOS 26+)
├── Sources/
│   ├── ClaudeRingsCore/            # UI와 무관한 로직 (테스트 대상)
│   │   ├── Account.swift           # Account, AppConfig, AccountStore
│   │   ├── KeychainService.swift   # 경로 정규화, 서비스명 변환
│   │   ├── TokenProvider.swift     # security CLI로 토큰 읽기
│   │   ├── Usage.swift             # Usage 모델, 응답 파싱
│   │   ├── UsageClient.swift       # API 요청, 상태 코드 해석
│   │   ├── UsageState.swift        # 상태, 색상 단계, 백오프, 리셋 시간 표기
│   │   ├── AccountPoller.swift     # 토큰 읽기 → 조회 → 401 재시도 → 상태 결정
│   │   └── SessionWatcher.swift    # 세션 PID 추적, 종료 판단
│   └── ClaudeRings/                # 앱 실행 파일
│       ├── main.swift              # NSApplication 설정
│       ├── AppDelegate.swift       # 조립, 세션 타이머
│       ├── UsageViewModel.swift    # 계정별 조회 루프
│       ├── RingsPanel.swift        # NSPanel
│       └── RingsView.swift         # SwiftUI + Liquid Glass
├── Tests/ClaudeRingsCoreTests/
├── Support/Info.plist              # .app 번들용 (LSUIElement)
├── scripts/
│   ├── probe-usage.sh              # 사용량 API 수동 확인 (토큰 비출력)
│   ├── build-app.sh                # swift build → .app 번들 → ~/Applications 설치
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
| UI | 수동 확인(라이트/다크, 여러 Space, 전체 화면 앱 위) |

## 10. 구현 순서

1. **API 검증**: 실제 사용량 API 응답을 확인하고 샘플을 픽스처로 저장(토큰은 마스킹)
2. Core 모듈을 TDD로 구현
3. 패널과 Liquid Glass UI
4. 빌드 스크립트와 `.app` 번들
5. 셸 함수 적용(`~/.zshrc` 수정은 사용자 확인 후)
