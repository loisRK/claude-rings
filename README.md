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

구현 완료 후 작성 예정입니다.

## 보안

- Keychain의 토큰은 **읽기만** 하며 갱신하거나 쓰지 않습니다.
- 토큰은 메모리에 캐싱하지 않고, 로그에도 남기지 않습니다.
- 최초 실행 시 macOS가 Keychain 접근을 묻습니다. **항상 허용**을 선택하세요.

## 참고

사용량 조회에 쓰는 `api/oauth/usage` 엔드포인트는 Anthropic의 비공식 API입니다. 예고 없이 바뀔 수 있습니다.

## License

[MIT](LICENSE)
