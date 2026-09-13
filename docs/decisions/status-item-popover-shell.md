# Status-item popover shell

Status: SUPERSEDED
Date: 2026-09-13
Superseded on 2026-09-13 by [Anchored status-item panel shell](status-item-panel-shell.md) because `NSPopover` necessarily rendered an arrow and its animated presentation state lost rapid toggle intent.
Supersedes: [Long-lived window shell](window-shell.md) and [Popup lifecycle architecture](popup-lifecycle.md)

## Context

Countdown Manager must behave as a normal menu-bar popover: anchored to its status item, non-draggable, automatically hidden when the user leaves it or changes Space, and reopened from the status item on the current Space. The standalone borderless-window migration visibly behaved like a centered movable utility window and did not satisfy that product outcome.

The migration's session-continuity outcome remains required. Hiding the surface must not reconstruct the SwiftUI root, discard an editor draft, reset list scroll, or reinterpret Save and Cancel.

## Decision

Use one strongly retained `NSPopover` with `.transient` behavior and one strongly retained `NSHostingController<ManagerView>` for the application session. Create both once and assign the hosting controller once. Show the popover relative to the current status-item button bounds; do not create, center, move or retain an application-owned utility window.

Closing affects visibility only. Do not replace the hosting controller or root from a popover close callback. The list hierarchy, editor session and draft remain owned by the retained SwiftUI hierarchy. Save and Cancel remain the only actions that commit or abandon editor work.

Use native transient dismissal for ordinary outside interaction. Application deactivation and the native active-Space notification also close a shown popover so keyboard app/Space switching has the same visibility result. Do not add mouse monitors, custom window positioning, detachment support, transient-state persistence or responder-reset machinery.

## Platform evidence

Apple defines `NSPopover` as content positioned relative to an existing view with an anchor. `show(relativeTo:of:preferredEdge:)` anchors it to the supplied positioning view, and `.transient` closes it for outside interaction. The popover retains a `contentViewController`; Countdown Manager separately retains that same controller, so visibility does not own the SwiftUI session lifetime.

- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- [show(relativeTo:of:preferredEdge:)](https://developer.apple.com/documentation/appkit/nspopover/show(relativeTo:of:preferredEdge:))
- [NSPopover.Behavior.transient](https://developer.apple.com/documentation/appkit/nspopover/behavior/transient)

## Consequences and verification

The AppKit-owned popover window may be an implementation detail and is not required to retain identity. Verification instead holds the hosting controller, content view, SwiftUI root, list, editor owner and draft identity across close/show. Real UI Smoke exercises this in an isolated process.

Actual anchoring, app-switch dismissal, Space dismissal, reopening on the current Space and non-draggability require the short manual acceptance described in `docs/VERIFICATION.md`; in-process calls and configuration inspection are only supporting evidence. No new harness mechanism is justified.

Domain behaviour, persistence, the single internal editor, embedded emoji choice, inline deletion, disclosure preferences, diagnostics, Save and Cancel are unchanged.
