import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
package final class EventEditorSession: ObservableObject {
    package enum Surface {
        case panel
        case desktop
    }

    @Published package private(set) var surface: Surface?

    package init() {}

    package var isPresented: Bool {
        get { surface == .panel }
        set {
            if newValue {
                _ = beginPanelEditor()
            } else {
                endPanelEditor()
            }
        }
    }

    package var hasActiveEditor: Bool { surface != nil }
    package var desktopIsPresented: Bool { surface == .desktop }

    package func beginPanelEditor() -> Bool {
        guard surface == nil else { return false }
        surface = .panel
        return true
    }

    package func endPanelEditor() {
        guard surface == .panel else { return }
        surface = nil
    }

    package func beginDesktopEditor() -> Bool {
        guard surface == nil else { return false }
        surface = .desktop
        return true
    }

    package func endDesktopEditor() {
        guard surface == .desktop else { return }
        surface = nil
    }
}

package struct UpdateConfiguration {
    package static func isValid(_ info: [String: Any], isolatedUpdateTest: Bool = false) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true else { return false }
        if url.scheme == "https" { return true }
        return isolatedUpdateTest && url.scheme == "http" && host == "127.0.0.1"
    }
}

package func updateRestartBlockReason(
    editorIsPresented: Bool, persistenceIsBusy: Bool, timerIsRunning: Bool
) -> String? {
    if editorIsPresented { return "Сохраните изменения или закройте редактор кнопкой «Отмена»." }
    if persistenceIsBusy { return "Дождитесь сохранения данных." }
    if timerIsRunning { return "Дождитесь окончания таймера или удалите его." }
    return nil
}

/// Owns Sparkle, while the existing state owners decide whether a restart is safe.
@MainActor
package final class ApplicationUpdates: NSObject, ObservableObject, SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate, NSMenuItemValidation {
    @Published package private(set) var isInstallationDeferred = false
    package private(set) var isInstallingUpdate = false
    package private(set) var isPresentingUpdateUI = false
    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()
    private var installHandler: (() -> Void)?
    private let restartBlockReason: () -> String?
    private let willPresentUpdateUI: () -> Void
    private let didFinishUpdateUI: () -> Void
    private let returnToApplication: () -> Void

    package init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        enabled: Bool = true,
        isolatedUpdateTest: Bool = false,
        willPresentUpdateUI: @escaping () -> Void = {},
        didFinishUpdateUI: @escaping () -> Void = {},
        returnToApplication: @escaping () -> Void = {},
        restartBlockReason: @escaping () -> String?
    ) {
        self.restartBlockReason = restartBlockReason
        self.willPresentUpdateUI = willPresentUpdateUI
        self.didFinishUpdateUI = didFinishUpdateUI
        self.returnToApplication = returnToApplication
        super.init()
        guard enabled, UpdateConfiguration.isValid(info, isolatedUpdateTest: isolatedUpdateTest) else { return }
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        controller = updaterController
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        do {
            try updaterController.updater.start()
        } catch {
            controller = nil
            // Avoid logging URLs or other server-controlled error content.
            DiagnosticLog.shared.record("updates.start failure")
        }
    }

    package var isAvailable: Bool { controller != nil }
    package var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates == true }
    package var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates == true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    @objc package func checkForUpdates(_ sender: Any?) {
        guard canCheckForUpdates else { return }
        // Sparkle has no before-show delegate hook for the checking progress window,
        // and does not repeat the found-update hook when refocusing an existing update.
        prepareForUpdateUI(source: "manual-check")
        controller?.checkForUpdates(sender)
    }

    @objc func toggleAutomaticChecks(_ sender: Any?) {
        automaticallyChecksForUpdates.toggle()
    }

    @objc func quitApplication(_ sender: Any?) {
        // Explicit Quit keeps its established meaning, including a persisted running timer.
        isInstallingUpdate = false
        NSApp.terminate(sender)
    }

    @objc func installDeferredUpdate(_ sender: Any?) {
        guard isInstallationDeferred else { return }
        if let reason = restartBlockReason() {
            showDeferredInstallationAlert(reason: reason)
            return
        }
        _ = resumeDeferredInstallation()
    }

    package func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)): return canCheckForUpdates
        case #selector(toggleAutomaticChecks(_:)):
            menuItem.state = automaticallyChecksForUpdates ? .on : .off
            return isAvailable
        case #selector(installDeferredUpdate(_:)): return isInstallationDeferred
        default: return true
        }
    }

    package func postponeInstallation(untilInvoking handler: @escaping () -> Void) -> Bool {
        guard restartBlockReason() != nil else { return false }
        installHandler = handler
        isInstallationDeferred = true
        DiagnosticLog.shared.record("updates.install deferred")
        return true
    }

    @discardableResult
    package func resumeDeferredInstallation() -> Bool {
        guard restartBlockReason() == nil, let handler = installHandler else { return false }
        installHandler = nil
        isInstallationDeferred = false
        // Sparkle's continuation bypasses postponement; termination checks safety again.
        isInstallingUpdate = true
        prepareForUpdateUI(source: "deferred-install")
        handler()
        return true
    }

    package var shouldCancelUpdateTermination: Bool {
        isInstallingUpdate && restartBlockReason() != nil
    }

    package func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard postponeInstallation(untilInvoking: installHandler) else { return false }
        // Let Sparkle finish processing the Install action before showing our modal.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isInstallationDeferred,
                  let reason = self.restartBlockReason() else { return }
            self.showDeferredInstallationAlert(reason: reason)
        }
        return true
    }

    package func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        prepareForUpdateUI(source: state.userInitiated ? "manual-update" : "scheduled-update")
    }

    package func standardUserDriverWillShowModalAlert() {
        prepareForUpdateUI(source: "sparkle-modal")
    }

    package func standardUserDriverWillFinishUpdateSession() {
        isPresentingUpdateUI = false
        didFinishUpdateUI()
        DiagnosticLog.shared.record("updates.ui session-finished")
    }

    private func prepareForUpdateUI(source: String) {
        isPresentingUpdateUI = true
        willPresentUpdateUI()
        DiagnosticLog.shared.record("updates.ui preparing source=\(source)")
    }

    private func showDeferredInstallationAlert(reason: String) {
        prepareForUpdateUI(source: "deferred-modal")
        let alert = NSAlert()
        alert.messageText = "Обновление готово. Перезапуск отложен."
        alert.informativeText = reason + " Затем в настройках нажмите «Обновление готово · установить…»."
        alert.addButton(withTitle: "Вернуться к работе")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        returnToApplication()
    }

    package func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        isInstallingUpdate = true
        DiagnosticLog.shared.record("updates.install starting")
    }

    package func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installHandler = nil
        isInstallationDeferred = false
        isInstallingUpdate = false
        DiagnosticLog.shared.record("updates.check aborted code=\((error as NSError).code)")
    }

    package func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
