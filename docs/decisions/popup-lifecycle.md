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
