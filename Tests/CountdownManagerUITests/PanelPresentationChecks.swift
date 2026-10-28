import CountdownManagerUI

func testPanelPresentationRequestLifecycle() {
    var state = PanelPresentationState()
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(!state.requestedVisible && !state.hasVisibleAcknowledgement)

    // A native hidden observation may complete after a fresh show request starts.
    state.requestShow()
    precondition(state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(!state.observeOcclusion(isVisible: false))
    precondition(state.requestedVisible && !state.hasVisibleAcknowledgement)
    precondition(!state.observeOcclusion(isVisible: true))
    precondition(state.requestedVisible && state.hasVisibleAcknowledgement)
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
        precondition(!state.observeOcclusion(isVisible: false))
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
    print("PASS panel presentation: pending show, visible acknowledgement, late hidden/visible, explicit hide and 200 rapid request sequences")
}
