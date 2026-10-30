import AppKit
import Carbon
import ServiceManagement
import Testing
@testable import iLaunchPad

@MainActor
private final class LoginServiceFixture: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var fails = false
    var registrations = 0
    func register() throws {
        registrations += 1
        if fails { throw NSError(domain: "test", code: 1) }
        status = .requiresApproval
    }
    func unregister() async throws { status = .notRegistered }
}

@Suite(.serialized)
@MainActor
struct LoginItemTests {
    @Test func initializationDoesNotRegisterAndExternalChangesRefresh() {
        let service = LoginServiceFixture()
        let controller = LoginItemController(service: service)
        #expect(!controller.isEnabled)
        #expect(service.registrations == 0)
        service.status = .enabled
        controller.refresh()
        #expect(controller.isEnabled)
        service.status = .notRegistered
        controller.refresh()
        #expect(!controller.isEnabled)
    }

    @Test func approvalAndUnregistrationReflectSystemState() async {
        let service = LoginServiceFixture()
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        #expect(controller.status == .requiresApproval)
        #expect(controller.isEnabled)
        #expect(!controller.isUpdating)
        await controller.setEnabled(false)
        #expect(controller.status == .notRegistered)
        #expect(!controller.isEnabled)
    }

    @Test func failedRegistrationDoesNotReportEnabled() async {
        let service = LoginServiceFixture()
        service.fails = true
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isUpdating)
    }

    @Test func loginAppleEventIsDifferentFromManualOpen() {
        #expect(!LoginItemController.isLoginLaunch(nil))
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        #expect(!LoginItemController.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(LoginItemController.isLoginLaunch(event))
        let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                            eventID: AEEventID(kAEReopenApplication), targetDescriptor: nil,
                                            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(!LoginItemController.isLoginLaunch(reopen))
    }
}
