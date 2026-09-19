import ClaudeRingsCore
import SwiftUI

struct RingsView: View {
    let model: UsageViewModel
    let actions: RingsActions
    let onSizeChange: @MainActor (CGSize) -> Void

    @State private var hovered: String?
    @Namespace private var glassNamespace

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(model.accounts) { account in
                        AccountBubble(
                            account: account,
                            status: model.status(for: account),
                            isActive: model.isActive(account),
                            isExpanded: hovered == account.name,
                            blockedUntil: model.blockedUntil(for: account),
                            now: context.date,
                            namespace: glassNamespace)
                        .onHover { inside in
                            withAnimation(.spring(duration: 0.35)) {
                                if inside {
                                    hovered = account.name
                                } else if hovered == account.name {
                                    hovered = nil
                                }
                            }
                        }
                    }
                }
            }
            .padding(8)
            .fixedSize()
            .gesture(WindowDragGesture())
            .contextMenu {
                Button("지금 새로고침", action: actions.refresh)
                Button("위치 초기화", action: actions.resetPosition)
                Button("설정 파일 열기", action: actions.openConfig)
                Divider()
                Button("종료", action: actions.quit)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        }
    }
}

private struct AccountBubble: View {
    let account: Account
    let status: AccountStatus
    let isActive: Bool
    let isExpanded: Bool
    let blockedUntil: Date?
    let now: Date
    let namespace: Namespace.ID

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    /// 429 Retry-After로 사용량 조회 API가 일시 차단된 상태인지(Claude 사용 한도 초과와는 다름).
    private var isBlocked: Bool { blockedUntil != nil }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                ZStack {
                    DualRing(
                        outer: session?.remainingPercent,
                        inner: weekly?.remainingPercent,
                        isLoading: status == .loading,
                        isDashed: status == .missing)
                    center
                }
                .frame(width: 40, height: 40)
                .overlay(alignment: .topTrailing) {
                    if isBlocked, status.usage != nil {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .offset(x: 2, y: -2)
                    }
                }

                if isExpanded {
                    details
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(3)
            .opacity(isStale ? 0.5 : 1)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID(account.name, in: namespace)

            HStack(spacing: 3) {
                Text(account.name)
                if isActive {
                    Circle().fill(.tint).frame(width: 3, height: 3)
                }
            }
            .font(.system(size: 9, weight: isActive ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private var center: some View {
        switch status {
        case .loading:
            EmptyView()
        case .expired:
            Text("만료")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        case .missing:
            Text("로그인\n필요")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case .error:
            if let blockedUntil {
                VStack(spacing: 1) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .medium))
                    Text(ResetFormatter.string(until: blockedUntil, now: now))
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        case .ok, .stale:
            VStack(spacing: 0) {
                Text(session.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(weekly.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            detailRow(title: "Session", window: session)
            detailRow(title: "Weekly", window: weekly)
            if let blockedUntil {
                detailRow(title: "조회", value: "일시 제한 · \(ResetFormatter.string(until: blockedUntil, now: now)) 후 재시도")
            }
        }
        .font(.system(size: 10, design: .rounded))
        .padding(.trailing, 7)
        .fixedSize()
    }

    private func detailRow(title: String, window: UsageWindow?) -> some View {
        detailRow(title: title, value: window?.resetsAt.map { "\(ResetFormatter.string(until: $0)) 후 리셋" } ?? "—")
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
        }
    }
}

private struct DualRing: View {
    let outer: Int?
    let inner: Int?
    let isLoading: Bool
    let isDashed: Bool

    @State private var pulse = false

    var body: some View {
        ringsContent
            .animation(.spring(duration: 0.6), value: outer)
            .animation(.spring(duration: 0.6), value: inner)
            .onChange(of: isLoading) { _, loading in
                // 로딩을 벗어나면 다음 로딩 진입 시 애니메이션이 다시 트리거되도록 리셋한다.
                if !loading { pulse = false }
            }
    }

    /// `.loading` 동안에만 존재하는 서브트리로 펄스를 격리한다. `isLoading`이 false가 되면
    /// 이 서브트리(그리고 그 안의 `repeatForever` 애니메이션)가 통째로 제거되므로,
    /// 로딩을 벗어난 뒤에도 펄스가 계속되거나 깜빡이는 문제가 생기지 않는다.
    @ViewBuilder
    private var ringsContent: some View {
        let rings = ZStack {
            ring(value: outer, lineWidth: 3.5).padding(1.5)
            ring(value: inner, lineWidth: 3).padding(7)
        }
        if isLoading {
            rings
                .opacity(pulse ? 0.35 : 0.1)
                .animation(.easeInOut(duration: 1).repeatForever(), value: pulse)
                .onAppear { pulse = true }
        } else {
            rings
                .opacity(1)
        }
    }

    private func ring(value: Int?, lineWidth: CGFloat) -> some View {
        let color = RingLevel(remaining: value).color
        let track = StrokeStyle(lineWidth: lineWidth, dash: isDashed ? [2, 3] : [])
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.15), style: track)
            Circle()
                .trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private extension RingLevel {
    var color: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        case .unavailable: .gray
        }
    }
}
