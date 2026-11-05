# Week-day creation — native development evidence

Status: **unreleased feature**, based on application version **1.20.5 / build 41**.
These images describe the feature working tree, not the published 1.20.5 package. No version
bump, release tag or publication is established by this evidence. The historical published-release
images and their [provenance](../PROVENANCE.md) remain unchanged.

## Source and exercised application

- Branch at archival: `codex/create-week-days`.
- Base HEAD: `d9ff494324de0ae623c694ed1b7fcbf479a32089`.
- The working tree was dirty; HEAD alone does not identify the feature implementation.
- Exercised app identifier: `local.countdownmanager.app`; version/build: `1.20.5 / 41`.
- Actual retained executable SHA-256:
  `476701c09f00e60f0d0d30b864678b59d9235ff64a4c3576217d82745dcdf0f6`.
  The executable bytes were hashed independently when archiving and match the capture manifest.
- Original local evidence directory:
  `.lavish/week-native-evidence/captures/countdown-week-captures-20261104-223632-53293`.
  Its tested application bundle remains local; the repository archive contains the PNGs,
  result, manifest and copied build/design metadata, rather than another app distribution.

[source-snapshot.json](source-snapshot.json) records hashes for 85 application-source/resource and
build-dependency files at archival, with the real base HEAD and dirty-tree status. It is explicitly
an archival working-tree snapshot, not an invented feature commit or a capture-time source attestation.
[capture-file-hashes.json](capture-file-hashes.json) records exact hashes for all 22 copied PNGs
and the four copied metadata/result files. The archive copies were compared byte-for-byte with
their originals.

## Build and capture provenance

The app's actual [NativeBuildProvenance.json](NativeBuildProvenance.json) and
[NativeDesignContract.json](NativeDesignContract.json) are copied unchanged from its resources.

- Compiler headers SDK: macOS **15.4**, at
  `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`.
- Swift frontend: the Xcode toolchain path recorded in the build metadata; Apple Swift **6.4**.
  The SDK location does not mean that the Swift frontend came from Command Line Tools.
- Deployment target and linked compatibility: **13.0**. These are separate from the actual
  compiler headers SDK; the images are not labelled as compiled with SDK 13.
- Design style: `native-calendar-graphite-v2`.
- The metadata's `renderedAppearanceVerified` remains `false`: build metadata does not certify
  drawing. The native rendering and visual review described below are separate observations.
- Capture method: `NSView.cacheDisplay`, in-process native rendering, **not** a compositor
  presentation screenshot or physical status-item capture.
- All captures use backing scale 2. Mini-panel PNGs are 780 × 1200; sheet PNGs are 860 × 1120;
  desktop-result PNGs are 2400 × 1856. Exact values are recorded per image in the
  [manifest](manifest.json).
- Every capture records `isKeyWindow: true` and `canBecomeKey: true`. Mini fixtures are isolated
  key-capable 390 × 600 `NSPanel`s using the same `canBecomeKey` override as production; they
  do not establish the status-item shell's physical activation or Spaces lifecycle.
- Light/Dark and the Sunday Light/Dark Increase Contrast pair are explicit capture overrides.
  Reduce Motion is enabled for every still; these images do not demonstrate animation smoothness.
- Dates and weather/event content are demonstration fixtures. Only the injected Store clock
  changes; the system clock and production event data are not test fixtures.

## Confirmed focused native result

The copied [ui-smoke-result.txt](ui-smoke-result.txt) reports **PASS: 4/4** for this retained app:

1. Thursday, 5 November 2026: empty/inline entry, three-date preview, Cancel, an ordinary event
   on the same date, shared-editor exclusion, retained hide/show, one-write durable creation and
   zero-write repetition. This case also exercises renamed-day skipping and a failed-write retry.
2. Saturday, 7 November: one-date Sunday preview with the same creation/cancellation and
   persistence boundaries.
3. Sunday, 8 November: next Monday–Sunday, 9–15 November, seven-date preview and creation.
4. A cold Sunday preview confirmed after the injected clock reaches Monday: first confirmation
   writes nothing, presents a six-day re-review notice, and the second explicit confirmation
   persists Tuesday–Sunday only.

The native scrolling check uses `NSScrollView`/`NSClipView` to reveal the seventh day while both
footer actions remain fixed. `week-sunday-desktop-bottom-light.png` records that lower scroll state.
Desktop dismissal is checked by native visibility, parent detachment and released editing ownership;
SwiftUI may retain detached hidden sheet content and registry entries after dismissal, so their
mere continued existence is not treated as an open sheet.

The [manifest](manifest.json) enumerates **22 PNGs**: empty and inline entry, Thursday mini/desktop
preview, a desktop write failure, desktop results, Saturday/Sunday previews, the Sunday contrast
pair and bottom scroll state, and midnight re-review. All 22 passed PNG signature/chunk-CRC,
compressed-payload and manifest-dimension validation during archival. The root agent visually
inspected all 22 through two contact sheets and three full selected images and reported no observed
button overlap or clipping. This does not establish every possible accessibility or display setting.

The current README uses these actual files:

- [week-desktop-result-dark.png](week-desktop-result-dark.png)
- [week-mini-action-light.png](week-mini-action-light.png)
- [week-sunday-mini-preview-dark.png](week-sunday-mini-preview-dark.png)

## Earlier attempts and remaining checks

Earlier failures remain separate from the final native 4/4 result. The local diagnostics under
`.lavish/week-native-evidence/` include:

- `native.log`: week instrumentation stopped at the desktop-lock assertion after the older
  single-day route completed; disabled-control registration order was corrected.
- `native-retry.log`: the completed-review Cancel check did not close the sheet. Source review
  found that the harness registered those callbacks only on appearance; the new actions were
  moved to the existing update-aware registration path. The subsequent dismissal diagnostics
  separately identified the retained-hidden-content assumption below; no sole-cause claim is made.
- `native-repeat-check.log`: the older single-day editor route failed before reaching the week
  fixture: the window was visible but not key, and `editor.title` had no native field/first
  responder. This failure was not declared a false positive or fixed outside the feature's scope.
  Earlier applicable single-day results retain their own source provenance; they are not combined
  into a current all-green campaign.
- `native-focused.log`: an assertion required detached hidden sheet registrations to become nil.
  Dismissal checks were corrected to the actual native visibility/detachment/ownership contract;
  the final dedicated week fixture then produced the separate 4/4 result above.

The existing single-day `empty-state` route and its assertions remain available unchanged.
`week`/`week-capture` now select only the focused week fixture; this is test selection, not deletion
of the older regression surface or a claim that the interrupted run passed.

The first selected external native-menu attempt opened the real menu and reached a 430 × 560
preview with hittable Create/Cancel controls, then failed its first-row accessible-date-label
assertion. The retained diagnostic observed an empty `label` but the complete native `StaticText`
semantic `value`: `Четверг, 5 ноября 2026, Будет создан`. The test driver was corrected to read
the actual semantic text from label/value while preserving the exact date and status assertions;
this did not mutate application behaviour. The earlier attempt remains a failed driver assertion,
not a passed test.

The final [xcui-acceptance.log](xcui-acceptance.log) reports
`testDesktopWeekCreationNativeMenuCancelSaveAndRepeat` **passed in 32.259 seconds**, one selected
test with zero failures and `TEST EXECUTE SUCCEEDED`. It used the actual host date, Wednesday,
4 November 2026, and the native `Создать 4 дня` action for Thursday–Sunday. The run exercised real
native-menu opening and selection, hittable sheet actions, Cancel with unchanged durable bytes,
one saved set with expected day defaults, preserved ordinary same-date content and favorite, and
disabled repeat creation followed by Cancel. The large `.xcresult` remains local under
`.lavish/week-native-evidence/xcui-acceptance.xcresult`; its text log is archived here.

This external result uses the separately built Xcode Debug target with the macOS 27.0 SDK shown
in its build log. It establishes that selected native input/persistence workflow, not the appearance
provenance of the SDK-15.4 capture bundle above. It does not prove all weekday starts, injected
midnight, failure retry, mini-panel external input, physical keyboard typing or VoiceOver speech.

The fresh [lint-acceptance.log](lint-acceptance.log) reports zero violations and zero serious
violations in 96 Swift files. The final [fast-acceptance.log](fast-acceptance.log) completed with
exit zero after the latest test-driver changes: native design checks passed 7 and 18 Python tests,
then CoreChecks and UIChecks passed, including the new week cases and existing deterministic
regressions. No Swift edits followed these final gates.

[verification-log-hashes.json](verification-log-hashes.json) records the three accepted log hashes
and the separate external test-driver source hash. The original
85-file capture source snapshot is unchanged; later external-driver diagnostics are not relabelled
as capture-app source changes.

The final accepted evidence is the required strict-lint/fast gates, this focused native 4/4 result
with 22 captures, and the selected external 1/1 menu workflow. Earlier failed attempts remain failed;
they are not folded into an all-green campaign. No universal UI regression coverage, live forecast,
updater installation/relaunch, physical midnight/wake, real status-item app-switch or Spaces
acceptance is claimed here.
