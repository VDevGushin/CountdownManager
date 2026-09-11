# Long-lived window shell

Status: ACCEPTED
Date: 2026-09-11
Implementation: PENDING
Supersedes: [Popup lifecycle architecture](popup-lifecycle.md)

## Context

The required lifecycle is create once → show/hide → preserve session state. Countdown Manager needs its menu-bar entry, event list and editor, not the historical transient presentation mechanism or duplicate convenience flows.

The previous shell accumulated root reconstruction, quick-subtask sheet teardown, local/global mouse monitors and responder restoration. Historical evidence is retained in the superseded decision; these mechanisms are not requirements for the new shell.

A minimal `MenuBarExtra(.window)` spike compiled and passed signature verification on macOS 26.6.2 with Xcode 26.6. Real outside-click and status-item-toggle scenarios could not be executed because the UI driver returned `timeoutReached`. Root identity, State, scroll position, editor/draft retention and continued text input were not verified. The conclusion was `MENUBAREXTRA NOT PROVEN`, not a demonstrated platform failure.

The Product Owner explicitly accepted the long-lived `NSWindow` direction after this result. Acceptance here records a design decision, not completed runtime verification.

## Decision

Use one ordinary, strongly retained `NSWindow` and one strongly retained `NSHostingController` with a stable root for the application session. Keep the existing `NSStatusItem` entry and accessory-application model.

Create the hierarchy once, optionally lazily. Hide with `orderOut`; reopen the same window with normal activation and key-window APIs. Disable release-on-close and route window closing to hiding. Do not reconstruct the root, steal first responder on each show, or emulate a transient popover through deactivation handlers or mouse monitors.

Presentation follows [PRODUCT.md](../PRODUCT.md). Use one internal event editor, an embedded emoji choice and explicit controls. Remove the quick-subtask sheet, nested action popovers, separate emoji popup and Restart UI. Maintain the list hierarchy across editor presentation; isolate inactive content from input and accessibility.

Transient editing/navigation state stays in memory. Do not add restoration storage, window-frame persistence, pixel-scroll persistence, internal SwiftUI-window introspection or a container compatibility layer. Existing checklist-collapse preferences are unaffected.

Domain validation, calendar semantics, serialized persistence, revision ordering, rollback, legacy JSON compatibility and diagnostic privacy remain unchanged. The persistence ADR remains active.

## Reasons and trade-offs

Explicit ownership makes container lifetime independent of visibility and removes the need to preserve historic popup mechanics. The product gives up automatic outside-click dismissal and duplicate editing paths. It gains a normal primary window whose working state survives hiding.

Apple documents that `orderOut` hides a window without releasing it. This supports the ownership mechanism; it does not prove every SwiftUI focus/scroll behaviour in the eventual implementation.

- [NSWindow.orderOut](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:))
- [NSWindow.isReleasedWhenClosed](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)

## Alternatives

- `MenuBarExtra(.window)`: not selected because the required continuity remained unproven; no restoration system will be built around it. This is not a claim that it necessarily recreates state.
- `NSPanel`: no auxiliary, floating or nonactivating-window requirement justifies its additional semantics for the primary UI.
- Transient `NSPopover`: superseded; retaining its secondary presentations would preserve avoidable lifecycle complexity.
- Multiple shell implementations or historical workaround layers: outside scope; no demonstrated need.

## Consequences and verification

The exact production scope and acceptance checklist are in [window-shell-migration.md](../plans/window-shell-migration.md). `ARCHITECTURE.md` distinguishes current code from target ownership until migration is complete.

Runtime continuity and keyboard behaviour remain unverified. Exercise real status-item clicks, native window close, outside interaction, reopen and text entry on the provenance-identified isolated bundle. Internal show/hide calls cannot substitute for those user actions. Follow `docs/VERIFICATION.md` for evidence selection and data isolation.

## Revisit

Revisit only if observed window behaviour prevents the product contract or the Product Owner changes that contract. Availability of another container alone is not a reason to reopen the decision. Do not resume MenuBarExtra research as part of the scoped migration.
