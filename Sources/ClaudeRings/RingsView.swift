import ClaudeRingsCore
import SwiftUI

struct RingsView: View {
    let model: UsageViewModel
    let actions: RingsActions
    let onSizeChange: @MainActor (CGSize) -> Void

    @State private var hovered: String?
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.accounts) { account in
                    AccountBubble(
                        account: account,
                        status: model.status(for: account),
                        isActive: model.isActive(account),
                        isExpanded: hovered == account.name,
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
        .padding(10)
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

private struct AccountBubble: View {
    let account: Account
    let status: AccountStatus
    let isActive: Bool
    let isExpanded: Bool
    let namespace: Namespace.ID

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    DualRing(
                        outer: session?.remainingPercent,
                        inner: weekly?.remainingPercent,
                        isLoading: status == .loading,
                        isDashed: status == .missing)
                    center
                }
                .frame(width: 56, height: 56)

                if isExpanded {
                    details
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(4)
            .opacity(isStale ? 0.5 : 1)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID(account.name, in: namespace)

            HStack(spacing: 3) {
                Text(account.name)
                if isActive {
                    Circle().fill(.tint).frame(width: 4, height: 4)
                }
            }
            .font(.system(size: 10, weight: isActive ? .semibold : .regular, design: .rounded))
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
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        case .missing:
            Text("로그인\n필요")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
        case .ok, .stale:
            VStack(spacing: 0) {
                Text(session.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(weekly.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
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
        }
        .font(.system(size: 11, design: .rounded))
        .padding(.trailing, 10)
        .fixedSize()
    }

    private func detailRow(title: String, window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(window?.resetsAt.map { "\(ResetFormatter.string(until: $0)) 후 리셋" } ?? "—")
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
        ZStack {
            ring(value: outer, lineWidth: 5).padding(2)
            ring(value: inner, lineWidth: 4).padding(10)
        }
        .opacity(isLoading ? (pulse ? 0.35 : 0.1) : 1)
        .animation(isLoading ? .easeInOut(duration: 1).repeatForever() : .default, value: pulse)
        .animation(.spring(duration: 0.6), value: outer)
        .animation(.spring(duration: 0.6), value: inner)
        .onAppear { pulse = true }
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
