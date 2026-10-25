# Countdown Manager 1.16.0 / build 31 — desktop polish and mini disclosure

Date: 2026-10-25, Europe/Moscow. Status: **PREPARED LOCALLY / NOT PUBLISHED**.
This combined follow-up replaces the prepared [attachment-overlay candidate](../attachment-overlay/PROVENANCE.md).
All earlier candidates, captures and failed attempts retain their own origin.

## Exact bundle and captures

Version **1.16.0**, build **31**, identifier `local.countdownmanager.app`, arm64.
Executable SHA-256: `69c29794d6607bc6b2a6dcae316fadfe49ceca34192061b2ce91c62e09493d2a`.
Local evidence root: `/private/tmp/countdown-desktop-polish.KcxzWE/`.
The candidate is `candidate/Countdown Manager.app`; the accepted native route is
`native-desktop-previews-settled-scroll-aqua` beneath that root.

[manifest.json](manifest.json) records **54 selected native PNGs**, their dimensions,
appearance metadata and SHA-256 values. All selected hashes and dimensions were verified.
The complete accepted route contains **124 verified PNGs**; its source manifest SHA-256 is
`17c03cd9ac5f0773b562df6d6657b4aa70407a01e358abb1738a23e487c3a2f3`.
The captures use isolated synthetic events, files and weather. Their method is
`NSView.cacheDisplay`: in-process native rendering, not a compositor recording.

## Fresh acceptance

The exact bundle passed native desktop **27/27**, in **55.659 seconds**, exit 0,
with unchanged before/after executable hashes and no reported main-thread stall or launcher timeout.
The desktop route includes the relevant shared mini-panel attachment scenarios; this is not
an additional full mini/editor suite result for this executable.
Strict SwiftLint reports **0 violations in 70 files**. Final CoreChecks/UIChecks passed
with exit 0. [acceptance.json](acceptance.json) combines the exact-bundle automated/native
checks, visual observations, artifact audit, source hashes and evidence limits.

The changed native scenarios cover:

- populated and empty saved details without duplicate editor-entry buttons; the header pencil
  still opens the shared editor with notes, subtasks and attachment state, and Cancel preserves data;
- direct checkbox actions, file rows and complete-library navigation;
- ordinary feed rows with calendar/title/remaining-time top alignment, date and weather on one
  line, horizontal checklist/paperclip summaries, narrow/wide panes and unchanged grid/favorite/detail roles;
- stable mini attachment-heading/count positions across repeated normal and Reduce Motion disclosures;
- shared Settings/file-library presentation and dismissal, disabled background throughout closing,
  outgoing controls unavailable for input/accessibility, owner removal, and Reduce Motion endpoints;
- long-list selection and final-event visibility after the native feed layout settles.

The documentation reviewer inspected six selected current renders: filled and empty details,
narrow and wide feed, loaded feed weather and the mini attachment summary. They show the single
pencil route, aligned feed rows, one date/weather line and readable mini sections. No actionable
static-layout issue was observed. These still images do not establish perceived animation quality.

## Geometry and long-scroll evidence

[Feed narrow geometry](feed-narrow-geometry.json) and [feed wide geometry](feed-wide-geometry.json)
use live NSView coordinates. At the narrow 278-point card and wide 743-point card, leaf/title/
remaining-label top coordinates agree. Date and forecast share a baseline, and the summary
contains checklist and file counts horizontally.

[Settled-layout observations](feed-scroll-layout-settled.json) retain the document changing
from 4602 to 4968.5 points and the final row becoming the expected 683 points wide. The driver
waits for that full-width row and three stable extent observations before scrolling to the end.
[Final feed visibility](browser-visibility-feed.json) records the last row at y=742, height=89,
inside the viewport y=55, height=800. This preserves the strict visibility requirement; there
is no product auto-scroll change.

## Motion evidence and its limits

Source implements one shared **200 ms ease-out** overlay style: opacity, a top-anchored
0.96→1 scale and a −12→0-point settle, reversed on dismissal. Settings and file libraries keep
their existing in-window roles; the editor remains a native sheet. Reduce Motion skips the
custom movement and dismissal delay. This follows the editor's visual family without claiming
identical system timing.

Motion filenames contain requested offsets, not guaranteed observation times. The manifest
retains both. Settings opening samples requested at 0/70/260 ms were actually observed around
**263/500/891 ms**; file-library samples around **331/625/1028 ms**. Synchronous cache rendering
cost exceeded the requested offsets. The frames and assertions establish modal guards, endpoints
and partial native rendering; they **do not certify the first 200 ms of compositor motion**,
physical-pointer fluency, frame rate or a frame-for-frame match with the native editor.
A screen recording of this exact final build's custom transitions has not been accepted here.

## Retained failed attempts

Failed build/fast logs and native attempts remain under the local evidence root:

- `build-closure-failed.log` / `fast-closure-failed.log`: missing `@escaping` annotation in the
  new overlay callback, corrected before the final bundle.
- `native-desktop-previews-accepted-aqua`, executable `ce2c75a4…`: FAIL after 7 scenarios;
  the new motion driver pressed before SwiftUI refreshed enabled state after editor Cancel.
  It now uses the existing enabled-wait action helper.
- `native-desktop-previews-driver-wait-fixed-aqua` (`050595ef…`) and
  `native-desktop-previews-feed-frame-diagnostic-aqua` (`9ed4a4ef…`): FAIL after 14 scenarios;
  wide-feed assertions exposed stale GeometryReader preference coordinates after retained custom
  Layout resizing. The diagnostic render was aligned; old frame subsets still had narrow/old positions.
  The compared views now use existing live NSView frame measurement, without loosening alignment checks.
- `native-desktop-previews-native-frames-aqua` (`78709a83…`): FAIL after 2 scenarios;
  broad native registration changed marker-value lifetime across favorite/ordinary replacement.
  The original logical StateObject ownership was restored with a separate frame-only NSView reference.
- `native-desktop-previews-frame-only-aqua` (`eabfd3a4…`) and
  `native-desktop-previews-native-viewport-aqua` (`b9c57ed7…`): FAIL after 24 scenarios;
  the driver scrolled while the animated feed's document extent was still growing, leaving an
  early clip position at y=3802. Live viewport receipts established the timing cause.
  Waiting for settled full-width layout resolves it while preserving strict last-row visibility.

The final `settled-scroll-aqua` PASS is separate from these retained failures. Measurement and
readiness corrections are not represented as application layout or auto-scroll fixes.

## Local signed-artifact audit

[artifact-audit.json](artifact-audit.json) records a public-key-only Apple CryptoKit audit:

- ZIP `CountdownManager-1.16.0-31.zip`: **5,805,574 bytes**, SHA-256
  `6c0368dbe09ea1f1e9e5b18cadd14545d337ff89f30ba29e1c9df2f14acf6553`.
- Signed appcast SHA-256: `5986a8584feb6e6ef0d12d09fad79bd5b4590f3beb622dcbee53289ea91dd502`.
- Both signatures pass; damaged messages and signatures are rejected.
- Production key/channel match the baseline; no test flags or loopback exemptions.
- Extracted strict/deep codesign passes; all **166** entries, symlinks and modes match the candidate.

This local audit does not publish artifacts or establish public download, first installation
or production update acceptance.

## Reused evidence and remaining scope

The [previous overlay acceptance](../attachment-overlay/acceptance.json),
[priority/limit acceptance](../priority-limit/acceptance.json) and older RC1/RC2 receipts retain
separate executable origins. Earlier full mini/editor routes, genuine updater and default-app
opening are reused only for unchanged behavior; they are not fresh routes on this executable.
The new motion's exact-build external compositor fluency remains unverified. Older macOS,
Intel, first-install Gatekeeper, forced mid-copy cancellation, cold first-launch default-app
opening and full VoiceOver speech retain their earlier limits. Production events are never
used as mutable QA fixtures.
