import ClaudeRingsCore
import SwiftUI

/// 메뉴바 항목의 콘텐츠. 계정별로 [로고 게이지][Session %] 위, [Weekly %] 아래를 가로로
/// 나열한다. `NSHostingView`로 `statusItem.button`에 실시간으로 얹으므로(ImageRenderer로
/// 스냅샷을 굽지 않음) 시스템 다크/라이트 모드가 바뀌면 자동으로 따라간다. 텍스트는
/// `.primary`만 쓰고 직접 검정/흰색을 지정하지 않는다.
struct MenuBarContentView: View {
    let model: UsageViewModel
    let theme: ThemeStore

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
    private var levelValue: Int? {
        switch (session?.remainingPercent, weekly?.remainingPercent) {
        case let (s?, w?): min(s, w)
        case let (s?, nil): s
        case let (nil, w?): w
        case (nil, nil): nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ServiceGaugeGlyph(service: service, percent: levelValue, color: theme.color(for: levelValue), size: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(sessionText)
                Text(weeklyText)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
        }
        .opacity(isStale ? 0.5 : 1)
    }

    private var sessionText: String {
        if session == nil, let blockedUntil {
            return "🕐\(ResetFormatter.string(until: blockedUntil, now: now))"
        }
        return session.map { "\($0.remainingPercent)%" } ?? "—"
    }

    private var weeklyText: String {
        weekly.map { "\($0.remainingPercent)%" } ?? "—"
    }
}
