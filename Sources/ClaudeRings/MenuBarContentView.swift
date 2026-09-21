import ClaudeRingsCore
import SwiftUI

/// 메뉴바 항목의 콘텐츠. 계정별로 [로고 게이지][Session %] 위, [Weekly %] 아래를 가로로
/// 나열한다. `NSHostingView`로 `statusItem.button`에 실시간으로 얹으므로(ImageRenderer로
/// 스냅샷을 굽지 않음) 시스템 다크/라이트 모드가 바뀌면 자동으로 따라간다. 텍스트는
/// `.primary`만 쓰고 직접 검정/흰색을 지정하지 않는다.
struct MenuBarContentView: View {
    let model: UsageViewModel
    let theme: ThemeStore
    /// 콘텐츠 너비가 바뀔 때마다 호출된다(계정 수는 고정이지만, 캐시가 없어 "—"만
    /// 보이던 첫 실행 후 실제 숫자가 채워지거나, 조회 일시 제한으로 시계+남은 시간
    /// 문구가 붙는 등 텍스트 폭 자체가 바뀔 수 있어서 한 번만 재는 것으로는 부족하다).
    var onWidthChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 9) {
                ForEach(model.accounts) { account in
                    MenuBarAccountView(
                        service: account.service,
                        status: model.status(for: account),
                        blockedUntil: model.blockedUntil(for: account),
                        now: context.date,
                        theme: theme)
                }
            }
            .padding(.horizontal, 6)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidthChange($0) }
        }
    }
}

private struct MenuBarAccountView: View {
    let service: ServiceID
    let status: AccountStatus
    let blockedUntil: Date?
    let now: Date
    let theme: ThemeStore

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    /// 컨트롤러 방침: 메뉴바의 게이지 하나는 Session·Weekly 중 더 급한 쪽(=더 낮은
    /// 잔여율)을 채움 비율·색 기준으로 삼는다. 어느 한도든 먼저 닥치는 쪽이 실제
    /// 위험이기 때문이다. 두 숫자 줄(Session 위·Weekly 아래) 자체는 그대로 각자의 값이다.
    /// 규칙 자체는 Core의 `RemainingPercent.mostCritical`에 있다(테스트로 검증됨).
    private var levelValue: Int? {
        RemainingPercent.mostCritical(session?.remainingPercent, weekly?.remainingPercent)
    }

    var body: some View {
        HStack(spacing: 4) {
            ServiceGaugeGlyph(service: service, percent: levelValue, color: theme.color(for: levelValue), size: 14)
            VStack(alignment: .leading, spacing: 0) {
                sessionLine
                Text(weeklyText)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
        }
        .opacity(isStale ? 0.5 : 1)
    }

    @ViewBuilder
    private var sessionLine: some View {
        if session == nil, let blockedUntil {
            HStack(spacing: 1) {
                Image(systemName: "clock")
                Text(ResetFormatter.string(until: blockedUntil, now: now))
            }
        } else {
            Text(session.map { "\($0.remainingPercent)%" } ?? "—")
        }
    }

    private var weeklyText: String {
        weekly.map { "\($0.remainingPercent)%" } ?? "—"
    }
}
