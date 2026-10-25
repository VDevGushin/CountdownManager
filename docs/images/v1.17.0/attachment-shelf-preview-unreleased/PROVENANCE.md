# Attachment shelf, compact details and quick preview — working-source evidence

Date: 2026-10-26. These images show the unreleased working branch after 1.17.0.
The test bundle retains version/build metadata **1.17.0/32**; publication is a separate action.

Native executable SHA-256:

```text
0316e4fbd00ab8bada98924201af32f6bb2d116820f74f919c2da26bbde6f8ce
```

Both native runs and the manual screen session used this exact executable. Runtime:
macOS **26.6.2 / 25G83**, arm64. Test data, defaults, logs and owned attachment copies lived
under separate marked homes in `/private/tmp/countdown-shelf-preview-qa.1iakbI/`.
Production Countdown data was not used as a fixture.

## Receipts

- [Desktop native](desktop-native.json): **27/27**, 52.507 seconds, unchanged executable, no recorded main-thread stall; 110 source PNGs.
- [Focused attachment native](attachments-native.json): **7/7**, 21.005 seconds, same executable, no recorded stall; 42 source PNGs.
- [External XCUITest](external-xcui.json): **2/2** actual pointer/keyboard/AX workflows. Xcode Debug is a separate test executable. After its successful build, only three in-process smoke frame-measurement IDs changed; feature-view, preview and Store code remained the same.
- [Manual acceptance](manual-acceptance.json): real photo/PDF/movie-poster/mini rendering, external Preview opening of the expected owned URL, return to the same mini selection and unchanged JSON/owned bytes/inventory across 31 files.
- [Strict lint](lint.log): zero violations in 75 files. [CoreChecks/UIChecks](fast.log): final `./verify.sh fast` passed. [Eval runner](eval-runner.log): 33 checks passed for the added verification-mode classification.
- [Source inputs](source-inputs.json): branch/base commit and 84 current input hashes. [Selected image manifest](manifest.json): dimensions, SHA-256 and capture method for every included image.

Native lifecycle/state observations are retained separately: [scroll return](desktop-preview-library-scroll-return.json),
[dismissal](desktop-preview-dismissal-diagnostic.json), [mini hide/reopen](mini-quick-preview-hide-reopen.json),
[owner deletion](desktop-preview-owner-deletion.json), [controlled expiry](desktop-preview-controlled-expiry.json).

## Capture method

Nine PNGs are current isolated native window renders. The four `quick-preview-*.jpg` images
are real computer-use compositor screenshots, preserving the screenshot tool's original JPEG
bytes. Quick Look uses service-backed rendering whose content is absent from `cacheDisplay`;
blank native-cache preview canvases are not used as evidence of rendered file content.

All dates, event titles, documents and media in these images are synthetic. The blue/gold image,
red/green PDF pages and color-bar movie are test content. Their appearance does not represent a
placeholder in the product. Static Light/Dark layouts and actual Quick Look pixels were inspected
by the designer after automated checks passed.

Only the selected 13 images are tracked here. Full native capture sets, test app and raw XCUITest
bundle remain in the temporary QA root. Raw OS recordings are not copied into repository images.
Historical release images are preserved in their original directories.

## Limits

`native-preview-requested` verifies URL/renderer ownership, not provider content readiness.
Hosted injected-clock expiry verifies the actual views and durable cleanup; it does not change
the system clock or prove a real system-midnight/Space transition. A native movie poster and
renderer release/recreation were verified; manually started native movie/audio playback was not
confirmed. Real VoiceOver, password-protected documents, third-party Quick Look providers and
runtime execution on macOS 13 remain outside this acceptance. Static images alone do not prove
the absence of every intermediate visual transient.
