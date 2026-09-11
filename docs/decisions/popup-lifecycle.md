# Popup Lifecycle Architecture

Status: SUPERSEDED

Superseded on 2026-09-11 by [Long-lived window shell](window-shell.md).

The decision below is retained solely as historical context. Its transient-container requirement, popup-specific semantics and presentation guardrails no longer govern the target shell. Current product behaviour is defined in `../PRODUCT.md`; implementation migration is pending.

## Context

Countdown Manager is a menu-bar application whose primary interface crosses the SwiftUI/AppKit boundary.

The application currently uses:

- an `NSStatusItem`;
- a transient `NSPopover`;
- SwiftUI content hosted through `NSHostingController`.

Popup visibility, SwiftUI view lifetime, sheets, first responder, application activation, and AppKit event routing can interact in ways that are not obvious from SwiftUI state alone.

Previous Countdown Manager regressions showed that changes in this area can produce severe lifecycle failures, including repeated SwiftUI/AppKit control rebuilding and UI stalls.

## Historical decision (no longer active)

### Primary container

The primary Countdown Manager interface remains hosted in a transient `NSPopover`.

Changing the primary container is an architectural change and should be supported by a concrete product or platform reason.

### Visibility and UI state lifetime

Transient popup visibility and user working-state lifetime are separate concerns.

Closing the transient popup must not implicitly define the lifetime of editing or navigation state when the product requires that state to survive ordinary dismissal.

The user-visible semantics are defined in `docs/PRODUCT.md`.

The implementation may use a stable hosting hierarchy or another mechanism that satisfies those semantics.

A specific state-preservation technique is not made permanent by this decision.

### SwiftUI/AppKit boundary

Changes involving:

- popover lifecycle;
- sheets;
- first responder;
- application activation;
- status-item routing;
- menu presentation;
- teardown and reconstruction

must be treated as platform-sensitive when their behaviour is not already established.

Use `.agents/skills/macos-platform-research/SKILL.md` when a technical choice materially depends on uncertain platform behaviour.

### Known SwiftUI Menu regression

Countdown Manager previously experienced a severe reconstruction failure involving SwiftUI menu infrastructure around `AppKitPopUpAdaptor` / `PlatformItemList`.

Do not reintroduce SwiftUI `Menu` into the previously affected popup action paths without current evidence that the old failure mode is no longer relevant.

This is a guardrail against a demonstrated regression, not a permanent claim that SwiftUI `Menu` is generally unsuitable for macOS.

### Presentation mechanisms

This decision does not permanently require or forbid SwiftUI `.sheet`, local popovers, event monitors, or other individual presentation mechanisms.

Choose them according to:

- current product behaviour;
- current platform evidence;
- the smallest mechanism that reliably satisfies the interaction.

Historical workarounds must not be retained solely because they once existed.

## Evidence

Historical commits relevant to this decision include:

- `6b0043d55f2b7003117830105ee8d42f4b5f3a68` — records the `AppKitPopUpAdaptor` / `PlatformItemList` reconstruction failure and related mitigation;
- `51c5552c2f3a0d6a583d9caf853033b09b67decf` — responder and transient-popover restoration;
- `e85233490d384d2501213dcfa487d76e53f93d7b` — sheet-end lifecycle handling;
- `50f72b792384f89127bfb2402f13fbd041f403b7` — responder restoration after reopen.

These commits explain historical risk.

They do not require preservation of the implementation that existed in those commits.

## Verification

Verification requirements are determined by the failure mode.

See `docs/VERIFICATION.md`.

When the contract depends on an actual external interaction, evidence must exercise that interaction rather than only invoke its resulting internal method.

## Revisit

Revisit this decision when:

- the primary popup architecture changes;
- a major macOS or SwiftUI/AppKit change materially affects the relevant lifecycle behaviour;
- authoritative or reproduced evidence shows that the known menu reconstruction failure is no longer relevant.
