import AppKit
import ClaudeRingsCore
import SwiftUI

/// 서비스별 로고 에셋을 찾는다. `Resources/logos/<service.rawValue>.png`가 없으면 nil을
/// 돌려줘 호출부가 `FallbackGlyph`(중립 대체 도형)를 쓰게 한다.
enum ServiceLogo {
    static func image(for service: ServiceID) -> NSImage? {
        guard let url = Bundle.module.url(
            forResource: service.rawValue, withExtension: "png", subdirectory: "logos")
        else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// 서비스 로고(또는 대체 도형)를 잔여율만큼 아래에서 위로 채워 보여주는 게이지.
/// 값이 있으면: 전체 도형을 낮은 투명도(0.18)로 깔고, 그 위에 잔여율 비율만큼의
/// 사각형으로 마스킹한 완전한 색을 겹친다(경로를 다시 그리지 않고 마스킹으로 구현).
/// 값이 없으면: 도형 자체를 낮은 투명도의 중립색으로만 보여준다(채움 없음).
struct ServiceGaugeGlyph: View {
    let service: ServiceID
    let percent: Int?
    let color: Color
    var size: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            if percent != nil {
                logoOrFallback.foregroundStyle(color.opacity(0.18))
            } else {
                logoOrFallback.foregroundStyle(.secondary.opacity(0.3))
            }
            if let percent {
                let fraction = CGFloat(max(0, min(100, percent))) / 100
                logoOrFallback
                    .foregroundStyle(color)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size * fraction)
                    }
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.5), value: percent)
    }

    @ViewBuilder
    private var logoOrFallback: some View {
        if let nsImage = ServiceLogo.image(for: service) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            FallbackGlyph()
        }
    }
}
