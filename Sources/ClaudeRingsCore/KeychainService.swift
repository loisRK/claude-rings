import CryptoKit
import Foundation

public enum KeychainService {
    public static let baseName = "Claude Code-credentials"

    /// `~`를 확장하고 끝의 `/`를 제거한다. Claude Code가 해시하는 경로와 같아야 한다.
    public static func normalize(_ path: String, home: String = NSHomeDirectory()) -> String {
        var result = path
        if result == "~" {
            result = home
        } else if result.hasPrefix("~/") {
            result = home + result.dropFirst()
        }
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// 기본 config(`~/.claude`)는 접미사가 없고, 그 외에는 경로 SHA-256의 앞 8자리를 붙인다.
    public static func serviceName(forConfigDir path: String, home: String = NSHomeDirectory()) -> String {
        let normalized = normalize(path, home: home)
        if normalized == normalize("~/.claude", home: home) {
            return baseName
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(baseName)-\(hex.prefix(8))"
    }
}
