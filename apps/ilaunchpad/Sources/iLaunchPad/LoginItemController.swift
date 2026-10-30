import AppKit
import Carbon
import Combine
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController: ObservableObject {
    static let shared = LoginItemController(service: SystemLoginItemService())
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?
    private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { refresh(); isUpdating = false }
        do {
            if enabled { try service.register() }
            else { try await service.unregister() }
        } catch {
            errorMessage = "无法更新登录项：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// Launch Services supplies the launch reason in the open-application event.
    /// An enabled login item alone does not mean this was a login launch.
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
            || event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}
