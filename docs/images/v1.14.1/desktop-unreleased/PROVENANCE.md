# Native desktop — unreleased branch evidence

Date: 2026-10-23, Europe/Moscow. Branch: `codex/desktop-window`, based on `364c4b5`.
This is the first native desktop implementation, not an HTML mockup and not a published release.
The bundle still reports 1.14.1 / 29; the published mini-app 1.14.1 is a different executable.

## Exact accepted build

- Executable SHA-256: `e4df29d331de27ff5438295b5def1239015f7e7c4a0ed256a7d811b07773933e`.
- Captures/results source: `/private/tmp/countdown-desktop-work.e9imkY/qa-accepted`.
- Retained human preview: `/private/tmp/countdown-desktop-preview.udecv3/Countdown Manager.app`.
- The moved preview executable was independently rehashed and matches the capture manifest.
- Eight native AppKit theme-frame PNG renders at 2×; dimensions and appearance are in `manifest.json`.
- Synthetic events, checklists and +14°C forecast only. No production events were used as mutable fixtures.
- No installation, commit, push or publication of this desktop implementation was performed.

## Acceptance evidence

- Strict full SwiftLint, CoreChecks and UIChecks passed on the integrated sources.
- `desktop-result.txt`: native desktop 7/7, including collection/feed, explicit-favorite-only
  presentation, shared panel checklist state, pane geometry, exclusive editor ownership in both
  directions, Save/Cancel and persistence, close veto, shared weather OFF and retained close/reopen.
- The linked-panel image is captured only after its rendered progress reads 2/2 and its completion
  marker is present, not merely after the shared data getter updates.
- Mini-panel regression results are retained here: full 23/23, collapse 2/2, editor 5/5 and
  continuity 8/8 on each of three runs. These exercised the preceding integrated bundle
  `d0e267…`; the final small focus-return routing and stronger rendered-progress wait were then
  exercised in the exact accepted desktop 7/7 run, not a repeated full mini-panel suite.
- Native captures were inspected in Light/Dark, including absent favorite and weather OFF.
  A separate QA agent reviewed current code and accepted captures without finding a blocker.
- External input on the hash-matched isolated preview confirmed Command-N opens the editor,
  Command-W retains its open draft, Cancel returns to the window, and Command-comma opens settings.
- Ordinary Command-W removed the desktop window without ending the process; Command-0 reopened
  the retained selection. The mini-panel footer opened its panel; Command-0 returned to desktop.
- Accessibility value-setting moved the native divider from 639 to 480 points. This is not
  evidence of physical mouse dragging or its extrema.
- Xcode project plist, shell syntax and whitespace checks passed. Earlier failed attempts
  (missing toolbar, registration metadata and capture timing) were corrected and superseded;
  they are not counted as passing acceptance.

## Limits

These captures are native window renders, not full-screen photographs or proof of Dock/Spaces.
Real Dock presence/reopen, app switching with panel dismissal, physical divider dragging at
both extrema, long-content extremes, VoiceOver speech, Increase Contrast and older macOS/Intel
remain unverified. Synthetic weather does not establish live provider or location-permission
behaviour. The preview is for owner review; desktop release readiness is not claimed.
