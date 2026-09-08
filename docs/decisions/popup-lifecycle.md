# Popup lifecycle and transient UI

Status: ACCEPTED

## Context

Countdown Manager is a menu-bar application whose primary UI runs inside a transient AppKit/SwiftUI popup.

Several regressions demonstrated that popup teardown, sheets, responder restoration and SwiftUI/AppKit control rebuilding can interact in non-obvious ways.

In particular, a previous freeze investigation showed runaway SwiftUI/AppKit menu rebuilding around `AppKitPopUpAdaptor` / `PlatformItemList` during popup-session reconstruction.

## Decision

Treat popup lifecycle as platform-sensitive architecture.

### Container

The status-item UI remains a transient `NSPopover`.

Do not use document-modal SwiftUI `.sheet` presentation over the transient popover for the main editor or quick-subtask editor flows.

Do not introduce SwiftUI `Menu` controls into the popup/event/subtask action paths without new platform evidence showing that the previous failure mode is no longer relevant.

Current action UI uses local action popovers where required.

### Editor presentation

The main editor and quick-subtask editor live inside the existing popover. `Inline` means an internal screen or state of that popover, not the technical insertion of a large form between list rows.

Preserve the application's existing visual language. Transitions must feel native and deliberate, avoid unnecessary flicker or layout jumps, and respect Reduce Motion when animation is used.

Under Product Freeze, do not introduce an independent redesign, decorative pattern, colour or feature while implementing this lifecycle change.

### Ordinary popover dismissal

An outside click is ordinary hiding of the transient popup, not `Cancel` or `Discard`.

Across ordinary close and reopen, preserve the user's working context through the existing UI hierarchy:

- scroll position;
- an open editor;
- an unsaved editor draft;
- quick-subtask draft and state.

Do not add manual persistence of pixel scroll offset or separate draft persistence/restoration solely for close and reopen unless platform evidence proves it necessary.

### Root hierarchy

Ordinary popup closure must not destroy or recreate the root `NSHostingController` or `ManagerView` merely for teardown. Preserve natural SwiftUI state continuity.

### Explicit actions

`Save`, `Cancel` and `Discard` retain their existing explicit semantics. An outside click alone must not lose user input.

### Outside-click mechanism

The first and preferred mechanism is native `NSPopover(.transient)` behaviour after the incorrect modal presentation has been removed.

Do not add an `NSEvent` monitor, mouse hook, forced-close workaround, separate panel/window or app-deactivation workaround in advance.

If native `.transient` behaviour is proven by real interaction not to satisfy this Product Contract after the architecture is corrected, establish the specific AppKit lifecycle cause, consult Apple documentation and choose the smallest platform-native lifecycle mechanism. Use an event monitor only after more native mechanisms are proven insufficient.

### Acceptance consequences

Installed black-box acceptance under `VERIFICATION.md` must exercise:

- a basic outside click;
- an outside click with the main editor focused;
- an outside click with the quick-subtask editor focused.

Product Owner manual QA is not a required READY gate.

## Trade-offs

This decision intentionally gives up some convenience of stock SwiftUI `Menu` behaviour and requires more explicit AppKit-aware lifecycle handling in affected action paths.

Local action popovers and explicit responder restoration add a small amount of custom code and platform coupling, but provide deterministic control over teardown and avoid a failure mode that previously caused severe UI stalls and memory runaway.

The guardrail can become stale as SwiftUI/AppKit evolves, so it must not be treated as permanent folklore: platform evidence should be re-checked when the decision's revisit conditions are met.

## Evidence trail

The detailed live samples, verification counts and intermediate investigation notes remain available in Git history. Key commits:

- `6b0043d55f2b7003117830105ee8d42f4b5f3a68` — `Fix editor teardown scroll freeze regression`; records the `AppKitPopUpAdaptor` / `PlatformItemList` runaway evidence, removes SwiftUI `Menu` from affected action paths and adds the editor teardown/root-scroll regression.
- `51c5552c2f3a0d6a583d9caf853033b09b67decf` — `Restore transient popover behavior after editor dismissal`; restores `.transient` interaction, key-window state and root first responder after editor dismissal.
- `e85233490d384d2501213dcfa487d76e53f93d7b` — `Restore popover after quick subtask sheet dismissal`; handles the AppKit sheet-end lifecycle before restoring the parent popover.
- `50f72b792384f89127bfb2402f13fbd041f403b7` — `Restore root responder when reopening popover`; captures the subsequent root-responder correction after reopen.

These references are evidence for this decision, not a requirement to preserve the old implementation unchanged. Re-check platform behaviour when the decision is revisited.

## Engineering rule

When changing popup, sheet, responder, menu or teardown behaviour:

1. use this decision for the established Product and Design Contracts and complete the pre-implementation check in `VERIFICATION.md`;
2. derive acceptance scenarios from those contracts before implementation;
3. use `macos-platform-research` and inspect existing lifecycle evidence;
4. identify any uncertain platform contract;
5. prefer a minimal spike if that platform contract is unclear;
6. verify at every layer required by `VERIFICATION.md`.

Do not add workaround layers before the root platform behaviour is understood.

## Revisit

Re-evaluate this decision after:

- a major SwiftUI/AppKit/macOS migration;
- material changes to popup architecture;
- authoritative evidence that the underlying platform behaviour changed.
