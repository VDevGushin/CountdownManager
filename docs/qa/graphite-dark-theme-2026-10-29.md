# Graphite dark appearance — 29 October 2026

Status: implemented and checked in the working tree, not released or installed.

## Accepted scope

The Product Owner selected Graphite after reviewing the Lavish comparison, then explicitly
extended it to the mini application, every dialog and popup. The acceptance source is the chat
message: «Согласен на графит - но там надо еще и мини приложение и все диалоги и всплывашки
это же темная тема считай будет». This authorizes the common dark palette, not layout, workflow,
data, icon-asset or Light-theme changes.

## Implementation

`AuroraInstrument` owns canvas #1C1D1F, surface #242527, elevated #2D2E31, primary text #ECECEE,
secondary text #B1B2B7 and rule rgba(139,141,149,.38). Timer surface is #292A2D; completed checks
use #7E8087 / #989AA1 in standard / increased contrast, and the increased-contrast rule is opaque
#B1B2B7. Light recipes, coral accent, green Today, ochre completion/warnings and semantic red are
unchanged. The sole local warm neutral on timer Play now uses the common canvas.

The shared appearance subscription also sets `NSApp.appearance`, covering native standalone
windows, menus and framework UI. Native file dialogs explicitly inherit the current host, with
the retained panel as fallback. The custom completion alert weakly inherits the retained panel.
No windows or views are recreated for these changes. Status-item assets still resolve against
the system status button's effective appearance. Document contents are not recolored.

The accepted style identity is `native-calendar-graphite-v2`; the source recipe golden was updated
for this explicit acceptance, retaining mutation rejection and all native component-family gates.

## Evidence

- Full SwiftLint: zero violations in 90 files; final quiet run also exited zero.
- Final `./verify.sh fast`: native source gate 7/7, native build contract 18/18, CoreChecks and
  UIChecks passed. The final run started after the last Swift edit.
- Native release-path build: compiler SDK 15.4, linked compatibility/deployment 13.0, version
  1.20.1 / build 37, updates disabled in the isolated test copy. The tested bundle was
  `/private/tmp/Countdown Graphite Validation.app`, built through `build.sh`.
- Desktop runtime: **31/31**. Includes Dark → Light → System, unchanged system status appearance,
  retained settings/editor ownership, nested diagnostic Save dark appearance and cancellation,
  grid/feed, inline deletion, links, file libraries, empty/search and persistence boundaries.
- General native runtime: **23/23**. Includes live completion-alert appearance-source changes,
  both themes / increased contrast, first-click and timed dismissal without focus change,
  settings Save dialog cancellation, editor and timer continuity, invalid/failed writes and retry.
- Mini/editor/settings/completion capture runtime: **5/5**, 31 PNGs.
- Material intake / native component fixtures: **1/1**, 16 PNGs covering desktop, mini, editor
  and text composer in Light/Dark × standard/increased contrast.
- Focused attachments/Quick Look runtime: **7/7**, 42 PNGs, including saved-order photo/PDF/video
  navigation, missing file, library return, renderer cleanup and owned-byte preservation.
- What's New: **1/1**, four Light/Dark × standard/increased-contrast captures.

These are six runtime modes with overlapping scenarios, not 68 distinct regression cases.
The same verified native bundle was reused for every runtime mode; every mode had its own marked
isolated home under `/private/tmp/countdown-graphite-qa/`. Production data was not used.
Results, manifests, provenance and PNG hashes are stored under
[`graphite-unreleased-2026-10-29`](../images/v1.20.1/graphite-unreleased-2026-10-29/PROVENANCE.md).

## Visual review

Inspected native captures of desktop feed, settings and inline deletion; mini list and editor;
standard/increased-contrast completion alert; standard dark / increased-contrast editor and mini
materials; text composer in Light/Dark; Light mini list; increased-contrast What's New; attachment
library and Quick Look shell. The new neutrals are consistent, text retains its hierarchy, and
Light retains its warm identity. This is selected capture review, not a pixel certification of all
224 generated PNGs. The existing native controls and SF Symbols were preserved.

## Initial failure and correction

The first desktop attempt stopped at the new diagnostic Dark assertion because the prior Light
capture override still superseded the preference. The test now clears that override while
exercising the real preference and restores it afterward. The unchanged final production code
passed the corrected desktop run. The failed first run is not counted as a pass.

## Limits

- The in-process `NSSavePanel` bitmap contains a uniform background rather than the system's remote
  dialog content. Its dark effective appearance, source-host identity, ownership and Cancel behavior
  passed; that PNG is not visual proof of its controls. Open-panel drawing, popup menus, tooltips
  and Sparkle's actual update windows were not individually captured in this run. They use native
  drawing and the selected app appearance; updater download/install behavior was not retested.
- Quick Look's remote document pixels are not guaranteed in in-process captures. The enclosing
  Graphite UI and renderer/navigation ownership were checked; file contents retain their colors.
- No external XCUITest, VoiceOver speech, physical screen/Space matrix or production install was
  run for this palette change. Motion/lifecycle coverage above is in-process native evidence.

Platform references used for the appearance decision:
[Apple NSAppearanceCustomization](https://developer.apple.com/documentation/appkit/nsappearancecustomization),
[Apple NSWindow.appearanceSource](https://developer.apple.com/documentation/appkit/nswindow/appearancesource),
[Sparkle standard user driver delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUStandardUserDriverDelegate.html).

## User follow-up and release boundary

The Product Owner supplied visible screenshots at 19:45 and 19:46 Moscow time showing brown
backgrounds in the native Save dialog and date popover despite the application's neutral surfaces.
These confirm a visual exception to the initial all-surfaces goal; Dark appearance propagation is
not evidence of exact Graphite RGB drawing. Wallpaper/desktop tinting is a possible cause, not
a locally confirmed A/B diagnosis. No system tinting preference was changed. The subsequent
1.20.2 release request follows this disclosure; its native help and public notes explicitly retain
this limitation rather than claiming full removal of native-window tinting.
