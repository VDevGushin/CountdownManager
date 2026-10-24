# Desktop activation and Spaces

Status: ACCEPTED
Date: 2026-10-23
Shipped: [1.15.0 / build 30](../releases/v1.15.0.md)

## Context

The owner requested research-led conventional macOS behavior after a recording showed a switch
to the desktop window's Space on opening and a switch back after closing it. Earlier conclusions
treated both transitions as defects; that overstates the evidence. The logs correlate closing
and accessory demotion with a Space change, but do not prove the precise system focus mechanism.

## Evidence

- [Apple: Work in multiple spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)
  documents that switching to an app defaults to switching to a Space containing its open windows.
  The user controls this with Mission Control settings and Dock Space assignment.
- [Apple: Move and arrange app windows](https://support.apple.com/en-ie/guide/mac-help/mchlp2469/mac)
  distinguishes closing a window from quitting: the app can remain open in the Dock until Quit.
- [Apple: ActivationPolicy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum)
  distinguishes ordinary Dock applications from accessory utilities. Neither mode requires
  dynamically changing the role on each window close.
- [Fantastical: Calendar Views](https://flexibits.com/fantastical/help/calendar-views)
  documents a menu-bar Mini Window alongside full calendar windows.
  [Fantastical settings](https://flexibits.com/jp/fantastical/help/settings) separately describe
  background operation after quitting the main app. This supports distinct surface/lifecycle
  roles, not a claim that every comparable app uses one identical implementation.
- [Drafts: Mac Share and Capture](https://docs.getdrafts.com/docs/extensions/capture-window)
  documents menu-bar access to its capture window. It is a quick surface alongside the main app,
  not evidence about Drafts' internal activation-policy implementation.

## Decision

Preserve menu-only accessory startup and launch-at-login behavior. The first explicit opening
of the retained desktop window promotes the same process to regular mode for the rest of the
session. Close, compact-mode switching and panel dismissal hide the relevant surface without
changing activation policy. Quit terminates the process; existing persisted timer-deadline
semantics remain unchanged. Do not add a second
process, preference, persistence migration, activation timer or deferred-demotion state.

Keep ordinary desktop Space behavior. Do not use `moveToActiveSpace` or `canJoinAllSpaces` on
the main window and do not change the user's global Mission Control preferences. Apple's
[moveToActiveSpace API](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace)
is a supported alternative for utilities, not a universal requirement for main windows. The
existing transient menu-bar panel continues to open on the active Space and hide when left.

## Verification boundary

The focused native runtime checks startup/promotion/retained regular policy, unchanged window
identity and timer, editor guards, panel switching and bounded panel visibility with real shell
callbacks. Tests of configuration and in-process activation are not physical Spaces evidence.
External acceptance must exercise opening from a different Space, ordinary close without a
forced role change, Dock reopen and menu-panel access under existing user settings. Do not claim
that all system-initiated Space transitions are forbidden or eliminated.
