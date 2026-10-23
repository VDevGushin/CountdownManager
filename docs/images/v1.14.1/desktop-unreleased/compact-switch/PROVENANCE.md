# Explicit compact-mode switching — unreleased native evidence

Date: 2026-10-23, Europe/Moscow. Branch: `codex/desktop-window`.
Bundle version/build remain 1.14.1/29; this is not the published 1.14.1 executable.
Earlier desktop evidence is retained in [the parent folder](../PROVENANCE.md).

## Exact build and captures

- Executable SHA-256: `52cc1a4aad8ccd54d76f934541008aaf51c2e76787c2b8b498c734fa587c1768`.
- Capture source: `/private/tmp/countdown-desktop-switch-captures/countdown-desktop-captures-20261023-022937-99507`.
- Retained preview bundle moved to `/private/tmp/countdown-desktop-preview.udecv3/Countdown Manager.app`.
- Eight native AppKit theme-frame PNGs, synthetic events and +14°C forecasts; see `manifest.json`.
- Earlier branch and release images are preserved; README references these refreshed captures.
- No production events, installed app, commit, push or release were changed.

## Verification

- Strict full SwiftLint and whitespace validation passed on the final source. CoreChecks and
  UIChecks passed before the final shell-only activation correction; those unchanged deterministic
  contracts are reused rather than repeating them. The final full application was rebuilt below.
- `./verify.sh desktop-capture` passed all 8 native scenarios; result is in `ui-smoke-result.txt`.
- New regression exercises the actual status-button action with `performClick`: showing and hiding
  the panel leaves the desktop visible. This is an in-process action, not physical menu-bar input.
- Focused desktop smoke now enables production shell lifecycle callbacks. Native panel readiness
  must hold continuously through a 500 ms event-processing interval; the status-item and explicit
  compact-mode paths both pass this stronger assertion.
- The registered footer action hides the desktop and opens the panel without changing activation
  policy during handoff. Accessory mode is restored only after genuine panel dismissal; returning
  to desktop cancels the deferred downgrade before hiding the panel.
  Returning through the panel's main-window action preserves the original hosting hierarchy,
  feed view, selected event and running timer deadline.
- The compact-mode action is rejected with a desktop editor or settings sheet open; existing
  draft close-veto, reverse panel ownership and persistence checks continue to pass.
- Previous full mini-panel regression remains evidence for its unchanged event-editing and timer
  contracts. The modified shell handoff/dismissal is accepted through the new focused lifecycle
  scenarios and external button input, not by claiming a repeated full general panel suite.
- External accessibility-button input on the hash-matched isolated visual preview confirmed
  `В мини-панель` opens a persistent `main.panel`, and its `Открыть основное окно` button returns
  the original selected event in `desktop.window`. Production lifecycle callbacks were active.
- Independent code review found no code blocker; its Dock-lifetime documentation correction
  was applied. Static captures alone do not establish the complete switching workflow.

## Superseded attempt

The earlier `7ce367…` build passed an insufficient smoke run that suppressed shell lifecycle
callbacks. Actual button input then exposed a delayed deactivation from changing activation
policy before showing the panel: the panel immediately hid. That result and manifest are retained
as `superseded-suppressed-lifecycle-*`, not accepted as final evidence. The final build removes
the premature policy transition and passes real callbacks plus the external button check.

## Limits

Real Spaces transitions, physical status-icon clicks, Dock visual presence, VoiceOver speech,
physical divider dragging and older macOS/Intel remain unverified. Weather is synthetic, not a
live provider check. Native rendering and these checks do not establish desktop release readiness.
