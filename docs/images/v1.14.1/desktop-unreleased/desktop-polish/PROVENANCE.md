# Desktop refinements — native capture provenance

2026-10-23, Europe/Moscow. Unreleased `codex/desktop-window`, bundle 1.14.1/29;
these images do not describe the published release.

- Source: `/private/tmp/countdown-desktop-polish.EihQ88/desktop-retry/Captures`.
- Executable SHA-256: `45dbefacd9435f8fde4b851b8449f7aeae98ed08cfca78f56cde6f1bb0812cd8`.
- Native desktop result: **PASS 11/11**; all 14 PNGs, exact manifest and result are retained here.
- Events, preferences and forecasts are isolated synthetic fixtures. Renders come from the
  native AppKit windows at 2×, not from the Lavish mockup or the user's personal desktop.
- README references the collection Dark, feed Light and running-timer frames. Those frames,
  finished timer and before/held-write frames were visually inspected. Every manifest PNG's
  dimensions/signature and the exercised executable hash were checked.
- The held-write fixture samples rendered enabled states and stable control frames six times
  during a controlled save, then checks accepted rapid inputs and a deferred editor. This is
  bounded transition evidence, not a claim about every frame or all external user interactions.
- `desktop-linked-panel.png` is raw cross-surface evidence captured during a checklist transition,
  not a settled visual reference; it is intentionally not used in the README.
- Earlier capture folders are preserved. Mini-panel design is unchanged; its focused regression
  passed 23/23 on the same executable. Real Spaces, physical Dock presentation, VoiceOver and
  historical external-driver limitations are not certified by these renders.

See [the focused report](../../../../qa/desktop-polish-2026-10-23.md) for failures, retest and scope.
