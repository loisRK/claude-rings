import ClaudeRingsCore
import SwiftUI

/// 메뉴바 항목의 콘텐츠. 계정별로 [색상 링][Session %] 위, [Weekly %] 아래를 가로로 나열한다.
/// 계정 수만큼 항목을 늘리지 않고, 이 뷰 하나를 단일 `NSStatusItem` 버튼 안에 넣는다.
struct MenuBarContentView: View {
    let model: UsageViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 9) {
                ForEach(model.accounts) { account in
                    MenuBarAccountView(
                        status: model.status(for: account),
                        blockedUntil: model.blockedUntil(for: account),
                        now: context.date)
                }
            }
            .padding(.horizontal, 6)
            .fixedSize()
        }
    }
}

private struct MenuBarAccountView: View {
    let status: AccountStatus
    let blockedUntil: Date?
    let now: Date

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    /// 링 색상은 Session 잔여율 기준(레이아웃상 링이 Session %와 같은 줄에 붙는다).
    /// Session 값이 없으면 Weekly 값으로 대체한다.
    private var ringValue: Int? { session?.remainingPercent ?? weekly?.remainingPercent }

    var body: some View {
        HStack(spacing: 4) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(sessionText)
                Text(weeklyText)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
        }
        .opacity(isStale ? 0.5 : 1)
    }

    private var ring: some View {
        let color = RingLevel(remaining: ringValue).color
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(ringValue ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 8, height: 8)
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
