# Popup lifecycle and transient UI

Status: ACCEPTED

## Context

Countdown Manager is a menu-bar application whose primary UI runs inside a transient AppKit/SwiftUI popup.

Several regressions demonstrated that popup teardown, sheets, responder restoration and SwiftUI/AppKit control rebuilding can interact in non-obvious ways.

In particular, a previous freeze investigation showed runaway SwiftUI/AppKit menu rebuilding around `AppKitPopUpAdaptor` / `PlatformItemList` during popup-session reconstruction.

## Decision

Treat popup lifecycle as platform-sensitive architecture.

Do not introduce SwiftUI `Menu` controls into the popup/event/subtask action paths without new platform evidence showing that the previous failure mode is no longer relevant.

Current action UI uses local action popovers where required.

Closing a transient editing session must restore a predictable root popup state rather than relying on accidental responder/window state.

Root UI recreation is not a default workaround for lifecycle problems.

Unsaved transient state must not survive popup closure.

## Evidence trail

The detailed live samples, verification counts and intermediate investigation notes remain available in Git history. Key commits:

- `6b0043d55f2b7003117830105ee8d42f4b5f3a68` — `Fix editor teardown scroll freeze regression`; records the `AppKitPopUpAdaptor` / `PlatformItemList` runaway evidence, removes SwiftUI `Menu` from affected action paths and adds the editor teardown/root-scroll regression.
- `51c5552c2f3a0d6a583d9caf853033b09b67decf` — `Restore transient popover behavior after editor dismissal`; restores `.transient` interaction, key-window state and root first responder after editor dismissal.
- `e85233490d384d2501213dcfa487d76e53f93d7b` — `Restore popover after quick subtask sheet dismissal`; handles the AppKit sheet-end lifecycle before restoring the parent popover.
- `50f72b792384f89127bfb2402f13fbd041f403b7` — `Restore root responder when reopening popover`; captures the subsequent root-responder correction after reopen.

These references are evidence for this decision, not a requirement to preserve the old implementation unchanged. Re-check platform behaviour when the decision is revisited.

## Engineering rule

When changing popup, sheet, responder, menu or teardown behaviour:

1. use `macos-platform-research`;
2. inspect existing lifecycle evidence;
3. identify the uncertain platform contract;
4. prefer a minimal spike if that contract is unclear;
5. add verification only at the layer required to protect the regression.

Do not add workaround layers before the root platform behaviour is understood.

## Revisit

Re-evaluate this decision after:

- a major SwiftUI/AppKit/macOS migration;
- material changes to popup architecture;
- authoritative evidence that the underlying platform behaviour changed.
