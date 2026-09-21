import Foundation

/// SwiftUI에 의존하지 않는 순수 RGBA 색상 표현. 사용자 지정 단계별 색상을
/// 저장·복원하는 데 쓴다(Core는 SwiftUI `Color`를 모른다).
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `"#RRGGBB"` 또는 `"#RRGGBBAA"`를 파싱한다("#"은 있어도 없어도 된다). 형식이
    /// 맞지 않으면 nil.
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let parsed = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let r, g, b, a: UInt64
        if hasAlpha {
            r = (parsed >> 24) & 0xFF
            g = (parsed >> 16) & 0xFF
            b = (parsed >> 8) & 0xFF
            a = parsed & 0xFF
        } else {
            r = (parsed >> 16) & 0xFF
            g = (parsed >> 8) & 0xFF
            b = parsed & 0xFF
            a = 0xFF
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }

    /// `"#RRGGBB"` 형식(알파는 담지 않는다. 사용자 지정 단계별 색은 항상 불투명으로 다룬다).
    public var hexString: String {
        func clamp(_ value: Double) -> Int { max(0, min(255, Int((value * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}

/// 잔여율 단계별(여유·주의·경고) 사용자 지정 색상. `RingLevel`의 3단계(`.unavailable` 제외)에 대응한다.
public struct LevelColors: Codable, Equatable, Sendable {
    public var good: RGBAColor
    public var warning: RGBAColor
    public var critical: RGBAColor

    public init(good: RGBAColor, warning: RGBAColor, critical: RGBAColor) {
        self.good = good
        self.warning = warning
        self.critical = critical
    }

    public static let `default` = LevelColors(
        good: RGBAColor(hex: "#34C759")!,
        warning: RGBAColor(hex: "#FFCC00")!,
        critical: RGBAColor(hex: "#FF3B30")!)

    /// 잔여율에 해당하는 단계 색을 고른다. 값이 없는 상태(`.unavailable`)는 사용자 지정
    /// 팔레트에 없으므로 nil(호출부가 회색 등으로 대체한다).
    public func color(for remaining: Int?) -> RGBAColor? {
        switch RingLevel(remaining: remaining) {
        case .good: good
        case .warning: warning
        case .critical: critical
        case .unavailable: nil
        }
    }
}
