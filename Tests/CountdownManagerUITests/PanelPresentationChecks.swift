import CountdownManagerUI

func testPanelPresentationRequestLifecycle() {
    var state = PanelPresentationState()
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(state.statusAction(press: nil, isOnActiveSpace: true) == .show)
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)

    // A native hidden observation may complete after a fresh show request starts.
    state.requestShow()
    precondition(state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(state.statusAction(press: nil, isOnActiveSpace: false) == .hide)
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(state.requestedVisible && state.hasVisibleAcknowledgement)
    precondition(state.statusAction(press: nil, isOnActiveSpace: true) == .hide)
    precondition(state.statusAction(press: nil, isOnActiveSpace: false) == .show)
    precondition(state.observeOcclusion(isVisible: false))
    state.requestHide()
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)

    // Late visible observations cannot resurrect a hidden request.
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)

    // Each explicit show starts unacknowledged, even after a previous visible presentation.
    state.requestShow()
    precondition(!state.observeOcclusion(isVisible: true))
    state.requestShow()
    precondition(!state.hasVisibleAcknowledgement)
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(state.requestedVisible)
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(state.observeOcclusion(isVisible: false))
    state.requestHide()

    // Deactivation/Space/close all use explicit requestHide, including before first acknowledgement.
    for acknowledged in [false, true] {
        state.requestShow()
        if acknowledged { precondition(!state.observeOcclusion(isVisible: true)) }
        state.requestHide()
        precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)
        precondition(!state.observeOcclusion(isVisible: true))
        precondition(!state.observeOcclusion(isVisible: false))
        precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)
    }

    for _ in 0..<200 {
        state.requestShow()
        // A second click can arrive while the first show is still waiting for WindowServer.
        precondition(state.statusAction(press: nil, isOnActiveSpace: false) == .hide)
        state.requestHide()
        precondition(!state.observeOcclusion(isVisible: false))
        precondition(state.statusAction(press: nil, isOnActiveSpace: true) == .show)
        state.requestShow()
        precondition(!state.observeOcclusion(isVisible: true))
        state.requestHide()
        precondition(!state.observeOcclusion(isVisible: true))
        state.requestShow()
        precondition(!state.observeOcclusion(isVisible: false))
        precondition(state.requestedVisible && !state.hasVisibleAcknowledgement)
        precondition(!state.observeOcclusion(isVisible: true))
        precondition(state.observeOcclusion(isVisible: false))
        state.requestHide()
    }

    // A click can deactivate the app before AppKit delivers that click to the status button.
    func press(_ number: UInt32) -> PanelPresentationState.StatusPress {
        .init(session: number, hardware: number)
    }
    precondition(state.statusAction(press: press(41), isOnActiveSpace: true) == .show)
    state.requestShow()
    precondition(!state.recordStatusPressDuringDeactivation(press(41), buttonIsDown: true))
    precondition(state.recordStatusPressDuringDeactivation(press(42), buttonIsDown: true))
    state.requestHide()
    precondition(state.statusAction(press: press(42), isOnActiveSpace: true) == .alreadyHidden)
    precondition(!state.requestedVisible)
    precondition(state.statusAction(press: press(43), isOnActiveSpace: true) == .show)
    state.requestShow()
    precondition(state.recordStatusPressDuringDeactivation(press(44), buttonIsDown: true))
    state.requestHide()
    precondition(state.statusAction(press: .init(session: 45, hardware: 44), isOnActiveSpace: true) == .alreadyHidden)

    // A new session-only press must not be mistaken for the previous hardware press.
    state.requestShow()
    precondition(state.recordStatusPressDuringDeactivation(.init(session: 46, hardware: 44), buttonIsDown: true))
    state.requestHide()
    precondition(state.statusAction(press: .init(session: 47, hardware: 44), isOnActiveSpace: true) == .show)

    // A pending dismissal association never consumes a different click or an accessibility action.
    for nextPress in [press(49), nil] {
        state.requestShow()
        precondition(state.recordStatusPressDuringDeactivation(press(48), buttonIsDown: true))
        state.requestHide()
        precondition(state.statusAction(press: nextPress, isOnActiveSpace: true) == .show)
    }
    state.requestShow()
    precondition(state.recordStatusPressDuringDeactivation(press(50), buttonIsDown: true))
    state.requestHide()
    state.clearStatusPressDuringDeactivation()
    precondition(state.statusAction(press: press(50), isOnActiveSpace: true) == .show)

    // AppKit can deliver a native menu-bar press before the synthetic session count advances.
    state.requestShow()
    precondition(state.recordStatusPressDuringDeactivation(press(50), buttonIsDown: true, usesNativeSession: true))
    state.requestHide()
    precondition(state.statusAction(press: press(50), isOnActiveSpace: true) == .alreadyHidden)
    precondition(state.statusAction(press: press(51), isOnActiveSpace: true) == .show)

    // A tracked close can end without another begin callback for the same click.
    state.requestShow()
    precondition(state.recordStatusPressDuringDeactivation(press(52), buttonIsDown: true, usesNativeSession: true))
    state.requestHide()
    let keyboardPress = PanelPresentationState.StatusPress(session: 52, hardware: 52, keyboard: 1)
    precondition(state.statusAction(press: keyboardPress, isOnActiveSpace: true) == .show)
    state.requestShow()
    precondition(!state.recordStatusPressDuringDeactivation(.init(session: 52, hardware: 52, keyboard: 2), buttonIsDown: true))

    // Switching to Finder with the pointer parked on the status item leaves no click to consume.
    let parkedPointerSample = press(53)
    for usesNativeSession in [false, true] {
        state.requestShow()
        precondition(!state.recordStatusPressDuringDeactivation(parkedPointerSample, buttonIsDown: false,
                                                               usesNativeSession: usesNativeSession))
        state.requestHide()
    }
    precondition(state.statusAction(press: parkedPointerSample, isOnActiveSpace: true) == .show)

    print("PASS panel presentation: pending show, native visibility, rapid toggles and deactivation before status action")
}
