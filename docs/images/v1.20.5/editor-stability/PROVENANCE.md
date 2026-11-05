# Native desktop editor appearance stability

Status: **unreleased development**, based on application **1.20.5 / build 41**.
The published package and [its historical images](../PROVENANCE.md) are unchanged. The earlier
[week-feature archive](../week-days/PROVENANCE.md) is also preserved; the current README images
below were refreshed from the newer executable that includes the card-style correction.

## Scope and privacy

The reported recording was inspected privately during the investigation. No user recording,
extracted frame, working-event export or private backup is included in this archive. The native
fixtures use generic event names and generated materials only. Their twelve events and four
generated PNG/PDF files are separate from production data.

The production change is restricted to the existing desktop event-card Button style:
`.plain` becomes standard native `.borderless`. The real Button, its action and accessibility
identity, and every background `disabled`, hit-testing, accessibility and shared-session guard
remain in place. No split-layout replacement, custom gesture or persistence migration was added.

## Exercised application and source identity

- Actual retained executable SHA-256:
  `af3c895dd73d3df920f5a81998d99183cb12207c12d58a6d38593c9b3dfddf92`.
  Its bytes were hashed when archiving and match both the editor and refreshed-week manifests.
- Identifier: `local.countdownmanager.app`; version/build: `1.20.5 / 41`.
- Local retained native evidence:
  `.lavish/week-jitter-investigation/evidence/countdown-editor-stability-captures-20261105-005339-63104`.
- The actual resource [NativeBuildProvenance.json](NativeBuildProvenance.json) and
  [NativeDesignContract.json](NativeDesignContract.json) are copied without alteration.
- Compiler headers SDK: **15.4** from the Command Line Tools SDK location. The actual Swift
  frontend is **Swift 6.4** at the Xcode toolchain path recorded in that metadata.
- Deployment target and linked compatibility: **13.0**, not a claim to have compiled using SDK 13.
- Design style: `native-calendar-graphite-v2`. The metadata retains
  `renderedAppearanceVerified: false`; separate runtime measurements and images supply the
  appearance evidence rather than changing that build-time value.

[source-snapshot.json](source-snapshot.json) records the real base HEAD, feature branch and dirty
working tree, with 85 application-source/resource/build-dependency hashes at archival. It is not
an invented feature commit or capture-time source attestation.
[archive-index.json](archive-index.json) contains exact copied-file hashes and PNG dimensions.
No prior release or week-feature evidence was overwritten.

## Bounded native style probe

The separate probe has no Store or working-data access. Its matching SDK-15.4 / linked-13 setup
is retained in [probe-provenance.json](probe-provenance.json). Within its fixed synthetic opaque
card frames, the enabled-to-disabled comparison measured mean absolute RGB-channel deltas:

| Native style | Light | Dark |
| --- | ---: | ---: |
| `.plain` | 5.2366 bytes | 6.6399 bytes |
| `.borderless` | 0 | 0 |

These are bounded probe observations, not a universal promise about every button or OS build.
The exact [disabled comparison](probe-disabled-comparison.json) also records unchanged frames.

The enabled `.plain` and `.borderless` probe images are **not pixel-identical**. The normalized
full-card comparison measured mean channel deltas of about 0.5021 in Light and 0.4776 in Dark,
with about 1.10% and 1.08% of pixels differing. The probe's centered outer stroke also differs from
the production card's inset `strokeBorder`, so those edge results are not proof of exact active
production-label parity. [Enabled comparison](probe-enabled-comparison.json) and
[text measurements](probe-enabled-text-parity.json) retain the actual observations. No exact
enabled focus/pressed/label raster-equivalence claim is made.

Separate ordinary pointer checks reported that an enabled probe Button incremented its counter,
the disabled Button did not, enabling it admitted a click and disabling it again rejected a click.
Tab/Option-Tab did not establish keyboard focus for any compared style on this host, so Space or
keyboard-focus parity is not credited. The production native transition test below has its own
more limited in-process action-admission checks.

## Confirmed native application regression

The copied [result](ui-smoke-result.txt) reports **PASS: 1/1**. The ordinary editor was opened and
cancelled twice in Light and twice in Dark in the retained native desktop, using:

- a separate Store/preferences and an injected 5 November 2026 clock;
- twelve generic nonfavorite events, with a multiline note and four generated materials on the
  selected event;
- 1400 × 640 native content, divider fraction 2/3 and browser offset 80 points;
- native animation enabled, without changing system appearance or user-data fixtures.

All **40 samples** in [editor-stability-trace.json](editor-stability-trace.json) measured zero
whole-card and title-ink mean RGB delta. The measured native geometry deltas were also zero,
inside the unchanged less-than-0.5-point limit. Cancel retained the complete fixture event JSON
and all four owned-file hashes. [trace-summary.json](trace-summary.json) records the archival
calculation, while the original trace remains unchanged.

Sampling requested 0, 33, 100 and 240 ms offsets for opening and cancellation, plus the attached
modal peak and fully dismissed state. Actual elapsed times are recorded and differ from those
requests; these are not frame-accurate WindowServer timestamps or a fixed-rate video capture.
`NSView.cacheDisplay` inspects local card drawing and excludes WindowServer-wide modal dimming;
it does not establish compositor presentation timing or subjective smoothness.

The archive contains **10 editor PNGs**: six full native-window images listed in
[manifest.json](manifest.json), plus four baseline ROI images. The four corresponding baseline
diagnostic JSON files are also retained. All ten PNGs passed structural CRC/decompression checks;
full-image dimensions match the original manifest. The ROI images are diagnostics, not additional
manifest-listed full-window captures.

The original manifest deliberately records `editorStabilityNativeAXValidated: false`: the native
AX baseline card was unsupported in that in-process inspection. It is not rewritten to claim that
the modal background was validated through an unavailable tree. Whole-application external AX
acceptance remains separate from the local rendering/data result.

## Earlier instrumentation failures and external status

The initial `before-fix.log` and subsequent `fixed-candidate.log` runs stopped at the baseline
ink/opaque-ROI admission guard **before entering the modal transition**. They did not reproduce
the reported appearance defect and are not negative-control failures proving the fix.
The initial three-byte semantic-token ink mask did not admit the observed solid ink. Diagnostic
inspection observed an offset of about 12.3 RGB bytes, and baseline glyph admission was adjusted
to 15 bytes. The cause of that offset is not established; this record does not attribute it to a
color profile. The temporal before/during/after comparison limit stayed at **one byte** throughout;
the accepted run then measured zero for all samples.

A focused-window computer-use check observed the generic baseline card buttons, selected a
different card, opened the ordinary editor and restored the selection after Cancel. While the
sheet was focused, its tree alone did not establish the entire parent application's AX exclusion.
The first whole-application XCUITest attempt failed before opening the editor because a smoke
registry identifier was queried as if it were a native AX identifier. The driver query was
corrected to the observed Russian native action label, keeping the intended assertions.
Neither that failed query nor a focused-sheet-only tree is credited as a full parent accessibility
pass. The separate final [ax-final.log](ax-final.log) then reports
`testDesktopEditorHidesBackgroundCardsWithStableStyle` **passed in 15.627 seconds**, one selected
test with zero failures and `TEST SUCCEEDED`. The actual whole-application query found the generic
baseline card, found it absent while the ordinary editor was active, then found it and the same
selected detail restored after Cancel. The complete isolated JSON bytes remained unchanged.
[external-ax-acceptance.json](external-ax-acceptance.json) records the accepted log and driver-source
hash. The large `.xcresult` remains local; no user fixture is copied into this archive.

That selected test uses a separate Xcode Debug build with SDK 27.0 and supplements native
input/accessibility evidence only. It does not replace the SDK-15.4 capture provenance, change the
original manifest's explicit in-process AX gap, or prove VoiceOver speech or keyboard-focus delivery.

The earlier accepted [fast-final.log](fast-final.log) and [lint-final.log](lint-final.log) are retained.
After the final test-driver-only native-label query correction, the complete gates were rerun:
[fast-complete.log](fast-complete.log) completed with exit zero, including design source/build
checks, CoreChecks and UIChecks; [lint-complete.log](lint-complete.log) reports zero violations
in all 96 Swift files. These are the latest complete acceptance gates. The test-driver query
correction does not change the capture application executable above.

## Fresh current README images

The same retained executable, **without rebuilding**, also passed the focused week fixture 4/4
again. [week-ui-smoke-result.txt](week-ui-smoke-result.txt) and the unchanged full
[week-manifest.json](week-manifest.json) record that run. The manifest describes the complete
22-image week run; this archive copies only its three current README selections:

- [week-desktop-result-dark.png](week-desktop-result-dark.png)
- [week-mini-action-light.png](week-mini-action-light.png)
- [week-sunday-mini-preview-dark.png](week-sunday-mini-preview-dark.png)

Those three PNGs were copied byte-for-byte and checked against their manifest dimensions and
executable hash. Together with the ten editor images they form 13 archived PNGs. Historical
week-feature images under `../week-days/` remain available with their earlier executable provenance.
No release, updater installation/relaunch, live forecast, keyboard/VoiceOver speech, physical
midnight/wake, real status-item app-switch or Spaces acceptance is claimed by this archive.
