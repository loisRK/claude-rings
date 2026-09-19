import ClaudeRingsCore
import SwiftUI

/// 임시 뷰. Liquid Glass 링 디자인은 Task 9에서 교체한다.
struct RingsView: View {
    let model: UsageViewModel
    let actions: RingsActions
    let onSizeChange: @MainActor (CGSize) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.accounts) { account in
                let usage = model.status(for: account).usage
                VStack {
                    Text(account.name)
                    Text("\(usage?.session?.remainingPercent ?? -1) / \(usage?.weekly?.remainingPercent ?? -1)")
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }
}
