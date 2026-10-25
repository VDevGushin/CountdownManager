# Countdown Manager 1.16.0 / build 31 — native sheets and editor previews

Date: 2026-10-25, Europe/Moscow. Status: **PREPARED LOCALLY / NOT PUBLISHED**.
This follow-up supersedes the custom Settings/file overlay of the
[desktop-polish candidate](../desktop-polish/PROVENANCE.md). Its 54 images, results and
200 ms imitation remain historical evidence, not current native-sheet acceptance.

## Exact executable and captures

Version **1.16.0**, build **31**. Executable SHA-256:
`5f88a554429be8ff9aae44036ef377cd9623c7a0cd4c439eee3ab1745f716254`.
[manifest.json](manifest.json) contains **42 selected images from 110 actual native PNGs**,
with verified dimensions and SHA-256 values. Source manifest SHA-256:
`b490693c6dbd71804e069a8eba78257753f3f46d5d25ebfffcbdf400e5e744e0`.
Events, attachments, preferences and weather are isolated demonstration fixtures.
Images use `NSView.cacheDisplay`: actual in-process native renders, not compositor recordings.

## Exact-build checks

The final executable passed native desktop **27/27** in **52.034 seconds**, exit 0,
with unchanged before/after executable hashes, no main-thread stall and no launcher timeout.
Final strict SwiftLint reports **0 violations / 71 files**. Final CoreChecks/UIChecks passed
with exit 0. Root acceptance and artifact-audit receipts retain their own exact evidence.
The desktop route includes focused shared mini/editor scenarios; a separate full mini/editor
suite, a new upgrade run and compositor-animation quality are not claimed for this executable.

The checks cover:

- one native SwiftUI sheet mechanism for Settings, file libraries and create/edit; native
  attachment, close/reopen, protected editor and route retention until native `onDismiss`;
- nested diagnostic Save/Cancel retaining Settings and releasing its export guard;
- shared editor previews at **36 × 36 pt**, before Save and after reopening: PNG, PDF, movie
  and TXT reach ready; corrupt input retains a usable type fallback;
- actual visible file rows in Light/Dark mini editor captures, without accepting controls
  belonging to a different native window or offscreen preview rectangles;
- the featured favorite's date/weather on a full-width row below title/calendar identity,
  including narrow/wide browser panes, while ordinary grid/detail roles remain unchanged.

Representative current renders: [Settings](desktop-settings-light.png),
[files](desktop-attachment-library-all-dark.png), [shared editor](editor-attachment-alignment-light.png),
[mini editor Light](mini-editor-attachment-previews-light.png),
[mini editor Dark](mini-editor-attachment-previews-dark.png),
[narrow favorite](desktop-weather-stable-feed-34.png) and
[wide favorite](desktop-weather-stable-collection-66.png).

## Physical platform probe and limits

[platform-probe.json](platform-probe.json) and
[platform-probe-evidence.jsonl](platform-probe-evidence.jsonl) identify a **separate isolated
probe executable**, its source/executable hashes and observed macOS **26.6.2** runtime.
The human confirmed an outside click closed the sheet. Logs record three consumed parent-content
clicks with `parentActions == 0`, and two parent clicks that retained a protected editor.
Inside-sheet close/cancel routes also completed. This establishes event routing and the native
sheet mechanism on that runtime; it is not a physical test of every final production route,
other macOS versions or the final animation's visual fluency. The probe did not establish a
physical click directly on a parent action button. Its nested Save behavior was not exercised;
final-build native checks cover the production nested-sheet lifecycle separately.

## Retained failed attempts

Earlier native runs remain associated with their original executable prefixes:
`318…` stopped after 3 checks, `0e43…` after 7, `7dc…` after 12 and `3c77…` after 16.
Driver corrections narrowed newly added favorite geometry markers to identity/metadata,
accepted modal-blocked parent hit testing, waited for sheet key/focus before text input,
and separated saved-row smoke IDs by hosting surface. Preview captures now scroll the
matching native window into view separately for each theme and retain strict viewport
containment. Public accessibility identifiers and product behavior were not weakened to
satisfy those criteria. These failed runs are not included in the final 27/27 result.

No publication, production-data migration or installation in `/Applications` follows from
these checks. Historical media-opening and updater receipts retain their original candidates.
