import Foundation
import CountdownManagerUI

@MainActor
func testApplicationUpdateSafety() {
    var info: [String: Any] = [
        "SUFeedURL": "https://updates.countdownmanager.org/appcast.xml",
        "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
        "SURequireSignedFeed": true,
        "SUVerifyUpdateBeforeExtraction": true,
    ]
    precondition(UpdateConfiguration.isValid(info))
    precondition(!UpdateConfiguration.isValid([:]))
    info["SUFeedURL"] = "http://127.0.0.1:8765/appcast.xml"
    precondition(!UpdateConfiguration.isValid(info))
    precondition(UpdateConfiguration.isValid(info, isolatedUpdateTest: true))
    info["SUFeedURL"] = "http://remote.countdownmanager.org/appcast.xml"
    precondition(!UpdateConfiguration.isValid(info, isolatedUpdateTest: true))
    info["SUFeedURL"] = "https://name:secret@updates.countdownmanager.org/appcast.xml"
    precondition(!UpdateConfiguration.isValid(info))
    info["SUFeedURL"] = "https://updates.countdownmanager.org/appcast.xml"
    info["SUPublicEDKey"] = "invalid-key"
    precondition(!UpdateConfiguration.isValid(info))
    info["SUPublicEDKey"] = Data(repeating: 7, count: 32).base64EncodedString()
    info["SURequireSignedFeed"] = false
    precondition(!UpdateConfiguration.isValid(info))

    var editorIsPresented = false
    var persistenceIsBusy = false
    var timerIsRunning = false
    var presentations = 0
    var finishes = 0
    let updates = ApplicationUpdates(
        info: [:], enabled: false,
        willPresentUpdateUI: { presentations += 1 },
        didFinishUpdateUI: { finishes += 1 }
    ) {
        updateRestartBlockReason(
            editorIsPresented: editorIsPresented, persistenceIsBusy: persistenceIsBusy,
            timerIsRunning: timerIsRunning
        )
    }
    precondition(!updates.isAvailable && !updates.canCheckForUpdates)
    // Exercise the public driver callback boundary; disabled checks must not hide the host.
    updates.checkForUpdates(nil)
    precondition(presentations == 0 && !updates.isPresentingUpdateUI)
    updates.standardUserDriverWillShowModalAlert()
    updates.standardUserDriverWillShowModalAlert()
    precondition(presentations == 2 && updates.isPresentingUpdateUI)
    updates.standardUserDriverWillFinishUpdateSession()
    precondition(finishes == 1 && !updates.isPresentingUpdateUI)
    var installations = 0
    precondition(!updates.postponeInstallation { installations += 1 })
    precondition(!updates.resumeDeferredInstallation() && installations == 0)

    // A draft created after checking/downloading must still block installation.
    editorIsPresented = true
    precondition(updates.postponeInstallation { installations += 1 })
    precondition(updates.isInstallationDeferred)
    precondition(!updates.resumeDeferredInstallation() && installations == 0)
    editorIsPresented = false
    persistenceIsBusy = true
    precondition(!updates.resumeDeferredInstallation())
    persistenceIsBusy = false
    timerIsRunning = true
    precondition(!updates.resumeDeferredInstallation())
    timerIsRunning = false
    precondition(updates.resumeDeferredInstallation() && installations == 1)
    precondition(presentations == 3 && updates.isPresentingUpdateUI)
    precondition(!updates.isInstallationDeferred && !updates.resumeDeferredInstallation())
    precondition(!updates.shouldCancelUpdateTermination)

    // Sparkle's continuation only runs once. A subsequent blocker is checked at termination.
    editorIsPresented = true
    precondition(updates.shouldCancelUpdateTermination)
    editorIsPresented = false
    timerIsRunning = true
    precondition(updates.shouldCancelUpdateTermination)
    timerIsRunning = false
    persistenceIsBusy = true
    precondition(updates.shouldCancelUpdateTermination)
    persistenceIsBusy = false
    precondition(!updates.shouldCancelUpdateTermination)
}
