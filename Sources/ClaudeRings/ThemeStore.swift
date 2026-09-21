import AppKit
import ClaudeRingsCore
import Foundation
import Observation
import SwiftUI

/// 잔여율 단계별(여유·주의·경고) 사용자 지정 색상을 `UserDefaults`에 저장하고 불러온다.
/// `@Observable`이라 팝오버의 `ColorPicker`가 값을 바꾸면 이를 읽는 모든 SwiftUI 뷰
/// (메뉴바 게이지 포함, 둘 다 실시간으로 호스팅되므로)가 즉시 다시 그려진다.
@MainActor
@Observable
final class ThemeStore {
    private(set) var colors: LevelColors
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let good = "claudeRings.theme.good"
        static let warning = "claudeRings.theme.warning"
        static let critical = "claudeRings.theme.critical"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colors = Self.load(from: defaults)
    }

    func setGood(_ color: Color) {
        colors.good = RGBAColor(color)
        persist()
    }

    func setWarning(_ color: Color) {
        colors.warning = RGBAColor(color)
        persist()
    }

    func setCritical(_ color: Color) {
        colors.critical = RGBAColor(color)
        persist()
    }

    func resetToDefault() {
        colors = .default
        persist()
    }

    /// 잔여율에 맞는 SwiftUI `Color`. 값이 없으면(`.unavailable`) 회색.
    func color(for remaining: Int?) -> Color {
        colors.color(for: remaining).map(Color.init) ?? .gray
    }

    private func persist() {
        defaults.set(colors.good.hexString, forKey: Keys.good)
        defaults.set(colors.warning.hexString, forKey: Keys.warning)
        defaults.set(colors.critical.hexString, forKey: Keys.critical)
    }

    private static func load(from defaults: UserDefaults) -> LevelColors {
        LevelColors(
            good: defaults.string(forKey: Keys.good).flatMap(RGBAColor.init(hex:)) ?? LevelColors.default.good,
            warning: defaults.string(forKey: Keys.warning).flatMap(RGBAColor.init(hex:))
                ?? LevelColors.default.warning,
            critical: defaults.string(forKey: Keys.critical).flatMap(RGBAColor.init(hex:))
                ?? LevelColors.default.critical)
    }
}

extension Color {
    init(_ rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension RGBAColor {
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(
            red: Double(resolved.redComponent), green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent), alpha: Double(resolved.alphaComponent))
    }
}
