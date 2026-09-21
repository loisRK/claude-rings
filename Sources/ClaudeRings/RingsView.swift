import ClaudeRingsCore
import SwiftUI

/// 팝오버 내용: 계정별 Session·Weekly 게이지 + 상세 정보, 색상 설정, 하단 버튼.
struct PopoverContentView: View {
    let model: UsageViewModel
    let theme: ThemeStore
    let loginItem: LoginItemModel
    let actions: RingsActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.accounts) { account in
                    PopoverAccountRow(
                        account: account,
                        status: model.status(for: account),
                        isActive: model.isActive(account),
                        isUnsupported: model.isUnsupported(account),
                        blockedUntil: model.blockedUntil(for: account),
                        now: context.date,
                        theme: theme)
                }

                Divider()

                colorSection

                Divider()

                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                    .font(.system(size: 11, design: .rounded))
                    .toggleStyle(.checkbox)

                if let error = loginItem.lastError {
                    Text(error)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("새로고침", action: actions.refresh)
                    Button("설정 열기", action: actions.openConfig)
                    Spacer()
                    Button("종료", action: actions.quit)
                }
                .font(.system(size: 11, design: .rounded))
            }
            .padding(14)
            .frame(width: 270)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("색상")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("기본값으로") { theme.resetToDefault() }
                    .font(.system(size: 10, design: .rounded))
            }
            ColorPicker("여유", selection: Binding(
                get: { Color(theme.colors.good) },
                set: { theme.setGood($0) }))
            ColorPicker("주의", selection: Binding(
                get: { Color(theme.colors.warning) },
                set: { theme.setWarning($0) }))
            ColorPicker("경고", selection: Binding(
                get: { Color(theme.colors.critical) },
                set: { theme.setCritical($0) }))
        }
        .font(.system(size: 11, design: .rounded))
    }
}

private struct PopoverAccountRow: View {
    let account: Account
    let status: AccountStatus
    let isActive: Bool
    let isUnsupported: Bool
    let blockedUntil: Date?
    let now: Date
    let theme: ThemeStore

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    /// 429 Retry-After로 사용량 조회 API가 일시 차단된 상태인지(Claude 사용 한도 초과와는 다름).
    private var isBlocked: Bool { blockedUntil != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(account.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isActive {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                }
                Spacer()
            }

            if isUnsupported {
                stateLabel("지원하지 않는 서비스: \(account.service.rawValue)")
            } else {
                switch status {
                case .loading:
                    stateLabel("불러오는 중…")
                case .expired:
                    stateLabel("만료")
                case .missing:
                    stateLabel("로그인 필요")
                case .error:
                    if let blockedUntil {
                        stateLabel("조회 일시 제한 · \(ResetFormatter.string(until: blockedUntil, now: now)) 후 재시도")
                    } else {
                        stateLabel("오류")
                    }
                case .ok, .stale:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 16) {
                            gaugeColumn(title: "Session", window: session)
                            gaugeColumn(title: "Weekly", window: weekly)
                        }
                        .opacity(isStale ? 0.5 : 1)
                        if let blockedUntil {
                            stateLabel("조회 일시 제한 · \(ResetFormatter.string(until: blockedUntil, now: now)) 후 재시도")
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func gaugeColumn(title: String, window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            ServiceGaugeGlyph(
                service: account.service,
                percent: window?.remainingPercent,
                color: theme.color(for: window?.remainingPercent),
                size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(title).foregroundStyle(.secondary)
                    Text(window.map { "\($0.remainingPercent)%" } ?? "—")
                        .fontWeight(.semibold)
                }
                Text(window?.resetsAt.map { "\(ResetFormatter.string(until: $0)) 후 리셋" } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, design: .rounded))
        }
    }

    private func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.secondary)
    }
}
