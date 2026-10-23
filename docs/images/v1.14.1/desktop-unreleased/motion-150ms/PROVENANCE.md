# Desktop transition — 150 ms comparison build

2026-10-23, unreleased `codex/desktop-window`, package 1.14.1/29.
Only the desktop grid/list easing duration changes from 0.1 to 0.15 seconds. Ease-in-out,
Reduce Motion, layout, typography, event data and mini-panel behavior are unchanged.

Source: `/private/tmp/countdown-motion-150ms/native/Captures`.
Release executable SHA-256: `ccd7cf2e6b8b0360fbfcb8736d73656e44e2fde6c196d67239052463bd77166e`.
Strict SwiftLint, CoreChecks, UIChecks and native desktop PASS 20/20. Forty-four current synthetic
PNGs, exact manifest and result are retained; the four README images are refreshed. PNG signatures,
dimensions/file coverage, executable hash and README references are verified. Historical images remain.

Native cache-display images do not establish compositor motion quality. The historical external
1/1 recording in `continuous-motion` demonstrates the same mechanism at 200 ms, not this speed.
No new external recording was run for the timing-only comparison; perceived 150 ms motion remains
for live user evaluation. Existing temporary card/label crossings are unchanged. No release,
`/Applications` installation, commit, push or merge is part of this task.
