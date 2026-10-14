import CountdownManagerUI
import Foundation
import IOKit.pwr_mgt

@MainActor
private final class FakeKeepAwakeAssertionAdapter: KeepAwakeAssertionAdapter {
    var createStatus: IOReturn = kIOReturnSuccess
    var releaseStatus: IOReturn = kIOReturnSuccess
    var createdID: IOPMAssertionID = 41
    var createCount = 0
    var releasedIDs: [IOPMAssertionID] = []

    func create() -> (status: IOReturn, id: IOPMAssertionID) {
        createCount += 1
        return (createStatus, createdID)
    }

    func release(_ id: IOPMAssertionID) -> IOReturn {
        releasedIDs.append(id)
        return releaseStatus
    }
}

@MainActor
func testKeepAwakeLifecycle() {
    withKeepAwakeDefaults { defaults, suite in
        testKeepAwakeAcceptedActions(defaults: defaults, suite: suite)
    }
    withKeepAwakeDefaults { defaults, suite in
        testKeepAwakeRestartsAndBundleReplacement(defaults: defaults, suite: suite)
    }
    withKeepAwakeDefaults { defaults, suite in
        testKeepAwakeRestoreFailures(defaults: defaults, suite: suite)
    }
    withKeepAwakeDefaults { defaults, _ in
        testKeepAwakeTerminationRetry(defaults: defaults)
    }
}

private let keepAwakePreferenceKey = "keepAwake.enabled"

@MainActor
private func withKeepAwakeDefaults(_ test: @MainActor (UserDefaults, String) -> Void) {
    let suite = "local.countdownmanager.keep-awake-checks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        preconditionFailure("Cannot create isolated Keep Awake preferences")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    test(defaults, suite)
}

@MainActor
private func testKeepAwakeAcceptedActions(defaults: UserDefaults, suite: String) {
    let adapter = FakeKeepAwakeAssertionAdapter()
    let controller = KeepAwakeController(defaults: defaults, adapter: adapter)
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(adapter.createCount == 0 && adapter.releasedIDs.isEmpty)
    precondition(defaults.object(forKey: keepAwakePreferenceKey) == nil)
    controller.setEnabled(false)
    controller.releaseForTermination()
    precondition(adapter.createCount == 0 && adapter.releasedIDs.isEmpty)

    // Failed creation must not report an active assertion or try to release its output ID.
    adapter.createStatus = kIOReturnError
    controller.setEnabled(true)
    precondition(!controller.isEnabled && controller.error != nil)
    precondition(!defaults.bool(forKey: keepAwakePreferenceKey))
    precondition(adapter.createCount == 1)
    controller.setEnabled(false)
    controller.releaseForTermination()
    precondition(adapter.releasedIDs.isEmpty)

    adapter.createStatus = kIOReturnSuccess
    controller.setEnabled(true)
    precondition(controller.isEnabled && controller.error == nil && adapter.createCount == 2)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))
    controller.setEnabled(true)
    controller.setEnabled(true)
    precondition(adapter.createCount == 2)

    // A release failure keeps the assertion owned and allows retry without a second create.
    adapter.releaseStatus = kIOReturnError
    controller.setEnabled(false)
    precondition(controller.isEnabled && controller.error != nil)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))
    precondition(adapter.releasedIDs == [41] && adapter.createCount == 2)
    controller.setEnabled(true)
    precondition(adapter.createCount == 2)
    adapter.releaseStatus = kIOReturnSuccess
    controller.setEnabled(false)
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(!defaults.bool(forKey: keepAwakePreferenceKey))
    precondition(adapter.releasedIDs == [41, 41])
    controller.setEnabled(false)
    precondition(adapter.releasedIDs == [41, 41])

    let restartedAdapter = FakeKeepAwakeAssertionAdapter()
    let restarted = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: restartedAdapter)
    precondition(!restarted.isEnabled && restarted.error == nil && restartedAdapter.createCount == 0)
}

@MainActor
private func testKeepAwakeRestartsAndBundleReplacement(defaults: UserDefaults, suite: String) {
    defaults.set("preserved", forKey: "unrelated.preference")
    let originalAdapter = FakeKeepAwakeAssertionAdapter()
    let original = KeepAwakeController(defaults: defaults, adapter: originalAdapter)
    original.setEnabled(true)
    original.releaseForTermination()
    precondition(!original.isEnabled && original.error == nil)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey) && originalAdapter.releasedIDs == [41])

    // A new owner with a fresh defaults instance models relaunch after replacing the bundle.
    // Version and application path do not participate in the preference key or domain.
    let replacementDefaults = UserDefaults(suiteName: suite)!
    let replacementAdapter = FakeKeepAwakeAssertionAdapter()
    replacementAdapter.createdID = 84
    let replacement = KeepAwakeController(defaults: replacementDefaults, adapter: replacementAdapter)
    precondition(replacement.isEnabled && replacement.error == nil && replacementAdapter.createCount == 1)
    precondition(replacementDefaults.string(forKey: "unrelated.preference") == "preserved")
    replacement.releaseForTermination()
    replacement.releaseForTermination()
    precondition(!replacement.isEnabled && replacementAdapter.releasedIDs == [84])
    precondition(replacementDefaults.bool(forKey: keepAwakePreferenceKey))

    let restoredAdapter = FakeKeepAwakeAssertionAdapter()
    let restored = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: restoredAdapter)
    precondition(restored.isEnabled && restoredAdapter.createCount == 1)
    restored.setEnabled(false)
    precondition(!defaults.bool(forKey: keepAwakePreferenceKey))
    let offAdapter = FakeKeepAwakeAssertionAdapter()
    let off = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: offAdapter)
    precondition(!off.isEnabled && offAdapter.createCount == 0)
}

@MainActor
private func testKeepAwakeRestoreFailures(defaults: UserDefaults, suite: String) {
    defaults.set(true, forKey: keepAwakePreferenceKey)
    let failedAdapter = FakeKeepAwakeAssertionAdapter()
    failedAdapter.createStatus = kIOReturnError
    let failed = KeepAwakeController(defaults: defaults, adapter: failedAdapter)
    precondition(!failed.isEnabled && failed.error != nil && failedAdapter.createCount == 1)
    precondition(failed.canDisableRestoration)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))
    failed.releaseForTermination()
    precondition(failedAdapter.releasedIDs.isEmpty && defaults.bool(forKey: keepAwakePreferenceKey))

    let healthyAdapter = FakeKeepAwakeAssertionAdapter()
    let healthy = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: healthyAdapter)
    precondition(healthy.isEnabled && healthyAdapter.createCount == 1)
    healthy.releaseForTermination()
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))

    failedAdapter.createStatus = kIOReturnSuccess
    failed.setEnabled(true)
    precondition(failed.isEnabled && failed.error == nil && failedAdapter.createCount == 2)
    precondition(!failed.canDisableRestoration)
    failed.releaseForTermination()
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))

    let cancelledAdapter = FakeKeepAwakeAssertionAdapter()
    cancelledAdapter.createStatus = kIOReturnError
    let cancelled = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: cancelledAdapter)
    precondition(!cancelled.isEnabled && cancelled.error != nil)
    precondition(cancelled.canDisableRestoration)
    cancelled.setEnabled(false)
    precondition(!cancelled.isEnabled && cancelled.error == nil && cancelledAdapter.releasedIDs.isEmpty)
    precondition(!cancelled.canDisableRestoration)
    precondition(!defaults.bool(forKey: keepAwakePreferenceKey))
    let nextAdapter = FakeKeepAwakeAssertionAdapter()
    let next = KeepAwakeController(defaults: UserDefaults(suiteName: suite)!, adapter: nextAdapter)
    precondition(!next.isEnabled && nextAdapter.createCount == 0)
}

@MainActor
private func testKeepAwakeTerminationRetry(defaults: UserDefaults) {
    let adapter = FakeKeepAwakeAssertionAdapter()
    let controller = KeepAwakeController(defaults: defaults, adapter: adapter)

    adapter.createdID = 42
    controller.setEnabled(true)
    precondition(controller.isEnabled && adapter.createCount == 1)
    adapter.releaseStatus = kIOReturnError
    controller.releaseForTermination()
    precondition(controller.isEnabled && controller.error != nil)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey) && adapter.releasedIDs == [42])
    controller.releaseForTermination()
    precondition(controller.isEnabled && controller.error != nil && adapter.releasedIDs == [42, 42])
    adapter.releaseStatus = kIOReturnSuccess
    controller.releaseForTermination()
    controller.releaseForTermination()
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(adapter.releasedIDs == [42, 42, 42] && adapter.createCount == 1)
    precondition(defaults.bool(forKey: keepAwakePreferenceKey))
}
