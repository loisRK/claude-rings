import Observation
import ServiceManagement

/// 로그인 시 자동 실행 여부를 `SMAppService.mainApp`으로 관리한다.
/// `SMAppService`는 실제 앱 번들(코드사인 포함)이 있어야 동작하므로,
/// `swift run`으로 실행할 때는 register/unregister가 실패할 수 있다. 그 경우
/// 앱을 죽이지 않고 `lastError`에 메시지를 남긴다.
@MainActor
@Observable
final class LoginItemModel {
    private(set) var isEnabled: Bool
    private(set) var lastError: String?

    init() {
        isEnabled = Self.currentStatus() == .enabled
    }

    func refresh() {
        isEnabled = Self.currentStatus() == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    private static func currentStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }
}
