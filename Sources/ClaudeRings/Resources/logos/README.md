# 서비스 로고 에셋

파일명은 `ServiceID.rawValue`와 같다(`claude.png` → `ServiceID.claude`). 새 서비스를 추가하면
`<service-id>.png`를 여기 추가한다. 없으면 중립 대체 도형(`FallbackGlyph`)이 대신 쓰인다.

## claude.png

- 출처: `https://claude.ai/favicon.ico` (Anthropic이 claude.ai에 공개 제공하는 파비콘)
- 가져온 날짜: 2026-09-21
- 처리: `.ico`에 내장된 PNG(48×48, 투명 배경)를 `sips -s format png`로 추출만 했다. 색상·형태는
  변경하지 않았다. 이 앱에서는 회색조 마스크로만 쓰고(칠하는 색은 사용자가 지정한 단계별 색),
  앱 자체의 번들 아이콘으로는 쓰지 않는다.
- 상표: "Claude"와 Claude 로고는 Anthropic의 상표다. 이 프로젝트는 Anthropic과 무관한
  비공식 도구다(README.md의 "상표" 절 참고).
