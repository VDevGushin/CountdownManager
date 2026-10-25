# Countdown Manager 1.18.0 / build 33 — release preflight evidence

Date: 2026-10-26. Status: **PUBLISHED_VERIFIED**, Latest is 1.18.0 / build 33.
The current release state belongs
in [the release document](../../releases/v1.18.0.md), while [acceptance.json](acceptance.json)
keeps completed and pending surfaces separate.

## Candidate identity

The [production candidate receipt](candidate-receipt.json) identifies version/build 1.18.0/33,
the unchanged production bundle ID, stable channel and existing production public key.
Executable SHA-256:

```text
e8c52b1af41e1e1cbb07e133a981caf04e107bd71627c9177a5fe1eee227b8e5
```

Fresh native runs used this executable before and after testing. Their separate marked homes
live under `/private/tmp/countdown-release-1.18.0.Ft9IdJfb/`; all dates, events and attachment
media were synthetic. Production Countdown data was not a test fixture.

## Completed exact-package evidence

- [Desktop native receipt](native-desktop-run.json) and [result](native-desktop-result.txt):
  **27/27**, 53.080 seconds, 110 source PNGs, unchanged executable, no launcher timeout or
  recorded main-thread stall. This covers window retention, shared Store/editor ownership,
  split geometry, theme, tasks, files, weather and relevant sibling workflows.
- [Focused attachment receipt](native-attachments-run.json) and [result](native-attachments-result.txt):
  **7/7**, 21.023 seconds, 42 source PNGs, the same executable and no recorded timeout/stall.
  It covers shelf bounds, saved-order navigation, search/nonzero-scroll return, current-file and
  owner removal, resource hide/reopen, read-only file trees and hosted controlled-clock expiry.
- The same exact candidate also passed [mini 23/23](native-mini-run.json),
  [editor 5/5](native-editor-run.json), [menu 3/3](native-menu-run.json) and
  [collapse 2/2](native-collapse-run.json), in 28.234 / 9.246 / 21.372 / 2.566 seconds respectively.
  Every receipt records unchanged executable hashes, no timeout and no recorded main-thread stall.
- [Final fast log](fast-final.log) contains CoreChecks and UIChecks PASS; [strict lint](lint-final.log)
  reports zero violations in 75 files.
- [External evidence](external-xcui.json) covers 28 unique cases: the full ABC-layout run passed
  27/28, followed by the sole affected diagnostic-path driver case passing 1/1 in 28.198 seconds.
  Its native path-clearing correction changed test code only; the signature-stripped QA host
  matches the candidate. This is combined 27 + 1 evidence, not a single all-green 28/28 run.
  Initial 24/28 and the full-run failure remain explicitly recorded. Raw OS videos are not copied.
- [Genuine update](genuine-update.json) passed real isolated 1.17.0/32 → 1.18.0/33 installation
  and relaunch at the same path: PID 60174 → one automatic PID 60377, observed independently
  before another UI read/manual open. Two synthetic events, 17 legacy attachments, JSON/markers
  across 35 files and Dark preference survived unchanged. The last file remained reachable at
  17/17. The disposable key was deleted and loopback server stopped; no production profile was used.
- Native observations remain separately readable: [scroll return](desktop-preview-library-scroll-return.json),
  [dismissal](desktop-preview-dismissal-diagnostic.json), [mini hide/reopen](mini-quick-preview-hide-reopen.json),
  [owner deletion](desktop-preview-owner-deletion.json) and [controlled expiry](desktop-preview-controlled-expiry.json).
- [Independent production artifact audit](artifact-audit.json): public-key-only Ed25519 signature
  checks and tamper rejection, safe ZIP member paths, correct feed fields, strict/deep extracted
  codesign and exact 166-entry byte/mode/symlink tree. [Cryptographic receipt](signature-verification.json).
  [Framework comparison](framework-baseline-comparison.json) shows the entire 151-entry framework
  tree matches the genuine previous release; all seven static resources also match it.

Signed local artifact hashes:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| CountdownManager-1.18.0-33.zip | 5,887,335 | `2e27b1cc53d531153f8576bc97d46957b4efa8b0f99a10da0d47c1117c93eb91` |
| appcast.xml | 1,299 | `7f713dd1f1e0979952845bb0c2e31e3e0dc0a81e0831c21bf57d09c26c70c7b9` |

## Selected current screenshots

[desktop/manifest.json](desktop/manifest.json) contains dimensions, appearance, capture method
and SHA-256 for the nine included current native PNGs and four original compositor JPEGs.
The PNGs come from the 110-image desktop run, not relabeled images from 1.17.0. Full source
capture sets remain in the temporary release root; historical release and working-source images
are preserved in their old directories.

These are `NSView.cacheDisplay` native renders. They establish static layout, not compositor
motion. Quick Look service-backed content is not captured by this method: blank cached preview
canvases are not included as evidence that an image/PDF/movie was rendered. The four JPEGs
are fresh, inspected computer-use compositor screenshots of the exact candidate: desktop
photo/PDF/movie-poster and mini-photo. They use a synthetic one-event/15-file marked manual home
under `/private/tmp/countdown-shelf-preview-qa.1iakbI/manual-home`. They prove those displayed
pixels, not playback of every provider. The isolated app was quit; Russian input was restored
through the UI and verified read-only as `com.apple.keylayout.Russian`.

## Public delivery and scope limits

All listed local gates, six native routes, combined external case coverage, actual upgrade and
public-key-only artifact audit are accepted. [Anonymous public delivery](publication.json) also
passed after publication: ZIP/version feed/stable feed are HTTP 200 with exact signed hashes;
Latest resolves to v1.18.0. The independent artifact auditor did not publish or access a private
key. Signed delivery and the isolated HTTP upgrade do not establish first-install trust.

The preflight runtime is macOS 26.6.2 / 25G83 / arm64. Metadata and Mach-O declare macOS 13.0
and arm64, not execution on every supported OS. Hosted clock expiry does not change the system
clock or prove a real midnight/Space transition. VoiceOver, password-protected documents,
all third-party Quick Look providers and manually started inline media playback retain their
documented acceptance boundaries. Ad-hoc plus Sparkle authenticity is separate from Apple
notarization or first-install Gatekeeper acceptance.

## Publication acceptance

Published as Latest. Anonymous ZIP, version feed and stable feed returned HTTP 200 and exact
locally signed bytes. Annotated tag points to the released source commit; public Latest redirect
resolves to v1.18.0. See [publication receipt](publication.json). The receipt closes the public-delivery gate.
