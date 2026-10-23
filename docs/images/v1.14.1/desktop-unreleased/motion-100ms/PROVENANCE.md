# Desktop transition — 100 ms comparison build

2026-10-23, unreleased `codex/desktop-window`, package 1.14.1/29.
Only the desktop grid/list easing duration changes from 0.2 to 0.1 seconds; Reduce Motion
still selects no animation. The layout, typography, data and mini-panel behavior are unchanged.

Source: `/private/tmp/countdown-motion-100ms/native/Captures`.
Release executable SHA-256: `dc8765bf8b8d9d45ea8120b6a8618ffb99dc3f135a0954a44040b387ecc78b1d`.
Strict SwiftLint, CoreChecks, UIChecks and native desktop PASS 20/20. Forty-four current synthetic
PNGs, manifest and result are retained, including the four refreshed README images. Historical
images are preserved. PNG signatures/dimensions/file coverage and executable hash are verified.

These are native cache-display renders, not compositor motion evidence. The previous external
1/1 recording under `continuous-motion` demonstrates the same mechanism at **200 ms**, not this
new speed. No new external video campaign was run for this single-parameter comparison; perceived
100 ms timing remains for the user's live evaluation. Existing temporary occlusion/label-crossing
limitations are unchanged. No release, `/Applications` installation, commit, push or merge occurs.
