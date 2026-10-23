# Desktop settings overlay — current native captures

2026-10-23, unreleased `codex/desktop-window`, package 1.14.1/29, not the published release.

Source: `/private/tmp/countdown-settings-overlay/native-final/Captures`.
Release executable SHA-256: `925987282bdca75027309e4dadfb4869b1bb10fe14f38c7cd9951a39120beae4`.
The retained manifest describes all 46 synthetic PNGs and their dimensions, appearance and capture
method. The native desktop result is PASS 21/21. Main README images are refreshed from this run;
historical captures remain unchanged.

Settings are a centered in-window pane with title-left / X-right, not a separate window. Dark and
Light settings and editor renders were visually inspected. The palette correction is applied only
at desktop hosts; mini-panel appearance, Back navigation and editor behavior are unchanged.
Grid/list motion remains 150 ms. No new compositor-motion recording was made.

Native images use `NSView.cacheDisplay`; they do not establish external mouse delivery or every
animation frame. The focused external XCUITest passed 1/1 on the same production source; the final
release rebuild subsequently changed only smoke-test hit-routing expectations for an open overlay.
Mini-panel smoke passed 23/23 with identical production code. See the
[focused QA report](../../../../qa/desktop-settings-overlay-2026-10-23.md) for provenance and limits.
