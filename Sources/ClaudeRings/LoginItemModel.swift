import Observation
import ServiceManagement

/// 로그인 시 자동 실행 여부를 `SMAppService.mainApp`으로 관리한다.
/// `SMAppService`는 실제 앱 번들(코드사인 포함)이 있어야 동작하므로,
/// `swift run`으로 실행할 때는 register/unregister가 실패할 수 있다. 그 경우
/// 앱을 죽이지 않고 `lastError`에 메시지를 남긴다.
///
/// `status`를 그대로 보관하는 이유: `register()`가 예외 없이 성공해도 상태가
/// `.enabled`가 아니라 `.requiresApproval`일 수 있다(시스템 설정에서 사용자 승인이
/// 더 필요함). 단순히 `Bool`만 들고 있으면 이 경우 체크박스가 아무 설명 없이
/// 조용히 꺼진 것처럼 보인다.
@MainActor
@Observable
final class LoginItemModel {
    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init() {
        status = Self.currentStatus()
    }

    /// 시스템 설정에서 사용자가 직접 로그인 항목을 바꿨을 수 있으므로, 팝오버를 열
    /// 때마다 호출해 최신 상태로 맞춘다.
    func refresh() {
        status = Self.currentStatus()
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

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func currentStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }
}
