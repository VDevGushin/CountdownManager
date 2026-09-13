# Long-lived window shell

Status: ACCEPTED
Date: 2026-09-11
Implementation: implemented in working tree; final release chrome/Spaces acceptance pending in the migration plan
Supersedes: [Popup lifecycle architecture](popup-lifecycle.md)

## Context

The required lifecycle is create once → show/hide → preserve session state. Countdown Manager needs its menu-bar entry, event list and editor, not the historical transient presentation mechanism or duplicate convenience flows.

The previous shell accumulated root reconstruction, quick-subtask sheet teardown, local/global mouse monitors and responder restoration. Historical evidence is retained in the superseded decision; these mechanisms are not requirements for the new shell.

A minimal `MenuBarExtra(.window)` spike compiled and passed signature verification on macOS 26.6.2 with Xcode 26.6. Real outside-click and status-item-toggle scenarios could not be executed because the UI driver returned `timeoutReached`. Root identity, State, scroll position, editor/draft retention and continued text input were not verified. The conclusion was `MENUBAREXTRA NOT PROVEN`, not a demonstrated platform failure.

The Product Owner explicitly accepted the long-lived `NSWindow` direction after this result. Acceptance here records a design decision, not completed runtime verification.

## Decision

Use one utility-styled, strongly retained `NSWindow` and one strongly retained `NSHostingController` with a stable root for the application session. Keep the existing `NSStatusItem` entry and accessory-application model. The concrete window is borderless but overrides key/main eligibility so ordinary SwiftUI text editing remains available. It has no title bar or traffic-light controls and uses `moveToActiveSpace`; when already visible on another Space, the show path orders out that same instance before activation and then brings it forward on the active Space.

Create the hierarchy once, optionally lazily. Hide with `orderOut`; reopen the same window with normal activation and key-window APIs. Disable release-on-close and route window closing to hiding. Application deactivation and the native active-Space notification hide the primary utility surface at the shell level, independently of the current SwiftUI screen or responder. Explicit status-item Show remains authoritative until AppKit reports that the application is active and the same window is key. These mechanisms change visibility only: the window, hosting controller, root, list, editor and draft remain alive. Do not reconstruct the root, steal first responder on each show, or implement dismissal with mouse monitors.

Presentation follows [PRODUCT.md](../PRODUCT.md). Use one internal event editor, an embedded emoji choice and explicit controls. Remove the quick-subtask sheet, nested action popovers, separate emoji popup and Restart UI. Maintain the list hierarchy across editor presentation; isolate inactive content from input and accessibility.

Transient editing/navigation state stays in memory. Do not add restoration storage, window-frame persistence, pixel-scroll persistence, internal SwiftUI-window introspection or a container compatibility layer. Existing checklist-collapse preferences are unaffected.

Domain validation, calendar semantics, serialized persistence, revision ordering, rollback, legacy JSON compatibility and diagnostic privacy remain unchanged. The persistence ADR remains active.

## Reasons and trade-offs

Explicit ownership makes container lifetime independent of visibility and removes the need to preserve historic popup mechanics. Native window deactivation hiding supplies temporary utility-surface visibility without coupling dismissal to root lifetime. The product gives up duplicate editing paths and gains a primary utility window whose working state survives every hide path.

An initial auto-hide implementation mixed Space observation with `windowDidResignKey`. Manual release acceptance showed that list-state Space transitions remained visible while an editor with a focused field hid through resign-key, proving that visibility still depended on responder state. A later `hidesOnDeactivate` plus occlusion implementation could cancel explicit status-item presentation. The accepted shell therefore keeps visibility ownership in application deactivation and the native active-Space notification, with no resign-key or SwiftUI-screen hooks.

Apple documents that `orderOut` hides a window without releasing it. This supports the ownership mechanism; it does not prove every SwiftUI focus/scroll behaviour in the eventual implementation.

- [NSWindow.orderOut](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:))
- [NSWindow.isReleasedWhenClosed](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)
- [NSWindow.CollectionBehavior.moveToActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace)

## Alternatives

- `MenuBarExtra(.window)`: not selected because the required continuity remained unproven; no restoration system will be built around it. This is not a claim that it necessarily recreates state.
- `NSPanel`: no auxiliary, floating or nonactivating-window requirement justifies its additional semantics for the primary UI.
- Transient `NSPopover`: superseded; retaining its secondary presentations would preserve avoidable lifecycle complexity.
- Multiple shell implementations or historical workaround layers: outside scope; no demonstrated need.

## Consequences and verification

The exact production scope and acceptance checklist are in [window-shell-migration.md](../plans/window-shell-migration.md). `ARCHITECTURE.md` distinguishes current code from target ownership until migration is complete.

Runtime continuity and keyboard behaviour are verified on macOS 26.6.2; supported-minimum macOS runtime and final release chrome/auto-hide/Spaces acceptance remain unverified. The migration plan records the exact results and limits. For future changes, exercise real status-item clicks, Command-W, application switching in both list and editor states, automatic hiding, reopen and continued text entry on the provenance-identified isolated bundle. Inspect chrome visually and exercise the actual cross-Space status-item path; configuration properties cannot substitute for those outcomes. Follow `docs/VERIFICATION.md` for evidence selection and data isolation.

## Revisit

Revisit only if observed window behaviour prevents the product contract or the Product Owner changes that contract. Availability of another container alone is not a reason to reopen the decision. Do not resume MenuBarExtra research as part of the scoped migration.
