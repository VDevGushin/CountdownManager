# Desktop weather stability and checklist motion

2026-10-24, unreleased `codex/desktop-window`, package 1.14.1/29, not the published release.

Source: `/private/tmp/countdown-desktop-stability/native/Captures`.
Release executable SHA-256: `1b8e5ec518983c45c0e6d510ddc23065c7eb0c379e3b61592889a6ba202544c2`.
All 64 PNGs use isolated synthetic events, forecasts and preferences. The exact capture manifest
and native desktop PASS 22/22 result are retained. Current README images come from this run;
historical images remain untouched. All PNG signatures/dimensions, manifest coverage, README
image references and executable provenance were verified.

Weather pending/loaded, missing, globally disabled/enabled and per-event disabled/enabled states
retain overview, card and inspector geometry in narrow/wide collection and feed. Root inspected
the native before/after weather renders and current main README compositions.

Checklist render series include normal completion/reopening and isolated Reduce Motion. Requested
filenames are not exact observation times: the first normal captures finish around 64–76 ms, and
later captures can overrun their nominal offsets. Actual timing is recorded per image. These
`NSView.cacheDisplay` renders and registry frames do not establish compositor animation quality.
Functional external eight-task completion/reopening passed separately; visual motion acceptance
requires its actual screen recording, not these stills.

The focused external test passed 1/1 on Debug executable
`02931560fd6a163035c9731780466b7fc59838d21f477f2e4c58fb60202efea3`.
The [privacy-safe application-only recording](motion/checklist-reorder.mp4) and intermediate strips
in `motion/` were reviewed by QA and root. Both directions show distinct intermediate row positions,
including a two-line label. Short row/text crossings remain. The original desktop recording is
private and is not included. Normal Reduce Motion was read as OFF without changing system settings;
the external video is not compositor proof for the reduced-motion mode or a frame-rate benchmark.
See the [focused report](../../../../qa/desktop-weather-checklist-2026-10-24.md).

Desktop-only view changes leave mini-panel production code and layout unchanged. Its preceding
23/23 control result is reused rather than reported as a new run. No release, merge, commit, push
or `/Applications` installation is part of this change.
