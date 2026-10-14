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

/// Persists user intent separately from the assertion owned by this application session.
@MainActor
package final class KeepAwakeController: ObservableObject {
    @Published package private(set) var isEnabled = false
    @Published package private(set) var error: String?

    private let adapter: any KeepAwakeAssertionAdapter
    private let defaults: UserDefaults
    private var assertionID: IOPMAssertionID?
    private static let enabledKey = "keepAwake.enabled"

    package var canDisableRestoration: Bool {
        !isEnabled && error != nil && defaults.bool(forKey: Self.enabledKey)
    }

    package convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, adapter: SystemKeepAwakeAssertionAdapter())
    }

    package init(defaults: UserDefaults, adapter: any KeepAwakeAssertionAdapter) {
        self.defaults = defaults
        self.adapter = adapter
        if defaults.bool(forKey: Self.enabledKey) {
            _ = createAssertion()
        }
    }

    package func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !isEnabled, createAssertion() else { return }
            defaults.set(true, forKey: Self.enabledKey)
        } else {
            guard releaseAssertion() else { return }
            // Also accepts OFF after a failed restore, when no assertion was acquired.
            defaults.set(false, forKey: Self.enabledKey)
            error = nil
        }
    }

    private func createAssertion() -> Bool {
        let result = adapter.create()
        guard result.status == kIOReturnSuccess else {
            error = "Не удалось включить «Не засыпать» (код \(result.status))."
            return false
        }
        assertionID = result.id
        isEnabled = true
        error = nil
        return true
    }

    private func releaseAssertion() -> Bool {
        guard let assertionID else { return true }
        let status = adapter.release(assertionID)
        guard status == kIOReturnSuccess else {
            // Keep ownership after failure so another attempt releases the same assertion.
            error = "Не удалось выключить «Не засыпать» (код \(status)). Попробуйте ещё раз."
            return false
        }
        self.assertionID = nil
        isEnabled = false
        error = nil
        return true
    }

    package func releaseForTermination() {
        _ = releaseAssertion()
    }
}
