import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
package protocol KeepAwakeAssertionAdapter: AnyObject {
    func create() -> (status: IOReturn, id: IOPMAssertionID)
    func release(_ id: IOPMAssertionID) -> IOReturn
}

@MainActor
private final class SystemKeepAwakeAssertionAdapter: KeepAwakeAssertionAdapter {
    func create() -> (status: IOReturn, id: IOPMAssertionID) {
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Countdown Manager: пользователь включил «Не засыпать»" as CFString,
            &id
        )
        return (status, id)
    }

    func release(_ id: IOPMAssertionID) -> IOReturn {
        IOPMAssertionRelease(id)
    }
}

/// Owns one session-only assertion; hiding the panel does not release it.
@MainActor
package final class KeepAwakeController: ObservableObject {
    @Published package private(set) var isEnabled = false
    @Published package private(set) var error: String?

    private let adapter: any KeepAwakeAssertionAdapter
    private var assertionID: IOPMAssertionID?

    package convenience init() {
        self.init(adapter: SystemKeepAwakeAssertionAdapter())
    }

    package init(adapter: any KeepAwakeAssertionAdapter) {
        self.adapter = adapter
    }

    package func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            let result = adapter.create()
            guard result.status == kIOReturnSuccess else {
                error = "Не удалось включить «Не засыпать» (код \(result.status))."
                return
            }
            assertionID = result.id
            isEnabled = true
        } else {
            guard let assertionID else { return }
            let status = adapter.release(assertionID)
            guard status == kIOReturnSuccess else {
                // Keep ownership after failure so another attempt releases the same assertion.
                error = "Не удалось выключить «Не засыпать» (код \(status)). Попробуйте ещё раз."
                return
            }
            self.assertionID = nil
            isEnabled = false
        }
        error = nil
    }

    package func releaseForTermination() {
        setEnabled(false)
    }
}
