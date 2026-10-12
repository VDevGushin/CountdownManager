import CountdownManagerUI
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
    let adapter = FakeKeepAwakeAssertionAdapter()
    let controller = KeepAwakeController(adapter: adapter)
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(adapter.createCount == 0 && adapter.releasedIDs.isEmpty)
    controller.setEnabled(false)
    controller.releaseForTermination()
    precondition(adapter.createCount == 0 && adapter.releasedIDs.isEmpty)

    // Failed creation must not report an active assertion or try to release its output ID.
    adapter.createStatus = kIOReturnError
    controller.setEnabled(true)
    precondition(!controller.isEnabled && controller.error != nil)
    precondition(adapter.createCount == 1)
    controller.setEnabled(false)
    controller.releaseForTermination()
    precondition(adapter.releasedIDs.isEmpty)

    adapter.createStatus = kIOReturnSuccess
    controller.setEnabled(true)
    precondition(controller.isEnabled && controller.error == nil && adapter.createCount == 2)
    controller.setEnabled(true)
    controller.setEnabled(true)
    precondition(adapter.createCount == 2)

    // Another application session starts off even while an existing owner is enabled.
    let nextAdapter = FakeKeepAwakeAssertionAdapter()
    let nextOwner = KeepAwakeController(adapter: nextAdapter)
    precondition(!nextOwner.isEnabled && nextOwner.error == nil)
    precondition(nextAdapter.createCount == 0 && nextAdapter.releasedIDs.isEmpty)

    // A release failure keeps the assertion owned and allows retry without a second create.
    adapter.releaseStatus = kIOReturnError
    controller.setEnabled(false)
    precondition(controller.isEnabled && controller.error != nil)
    precondition(adapter.releasedIDs == [41] && adapter.createCount == 2)
    controller.setEnabled(true)
    precondition(adapter.createCount == 2)
    adapter.releaseStatus = kIOReturnSuccess
    controller.setEnabled(false)
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(adapter.releasedIDs == [41, 41])
    controller.setEnabled(false)
    precondition(adapter.releasedIDs == [41, 41])

    adapter.createdID = 42
    controller.setEnabled(true)
    precondition(controller.isEnabled && adapter.createCount == 3)
    adapter.releaseStatus = kIOReturnError
    controller.releaseForTermination()
    precondition(controller.isEnabled && controller.error != nil)
    precondition(adapter.releasedIDs == [41, 41, 42])
    adapter.releaseStatus = kIOReturnSuccess
    controller.releaseForTermination()
    controller.releaseForTermination()
    precondition(!controller.isEnabled && controller.error == nil)
    precondition(adapter.releasedIDs == [41, 41, 42, 42] && adapter.createCount == 3)
}
