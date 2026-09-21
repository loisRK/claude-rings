import AppKit
import ClaudeRingsCore
import Foundation
import SwiftUI

/// 서비스별 로고 에셋을 찾는다. `Resources/logos/<service.rawValue>.png`가 없으면 nil을
/// 돌려줘 호출부가 `FallbackGlyph`(중립 대체 도형)를 쓰게 한다.
@MainActor
enum ServiceLogo {
    private static var cache: [ServiceID: NSImage?] = [:]
    private static var warnedMissing: Set<ServiceID> = []

    static func image(for service: ServiceID) -> NSImage? {
        if let cached = cache[service] { return cached }
        let resolved = load(for: service)
        cache[service] = resolved
        if resolved == nil, !warnedMissing.contains(service) {
            warnedMissing.insert(service)
            FileHandle.standardError.write(
                Data("claude-rings: \(service.rawValue) 서비스의 로고 에셋을 찾지 못해 대체 도형을 씁니다\n".utf8))
        }
        return resolved
    }

    private static func load(for service: ServiceID) -> NSImage? {
        // Package.swift가 리소스를 `.copy`로 처리해 logos/ 폴더 구조가 보존되므로
        // 우선 그 경로로 찾고, 혹시 `.process`로 평평해진 배치를 쓰더라도 동작하도록
        // 폴더 없이 파일명만으로도 한 번 더 찾아본다.
        if let url = Bundle.module.url(
            forResource: service.rawValue, withExtension: "png", subdirectory: "logos"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.module.url(forResource: service.rawValue, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
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
