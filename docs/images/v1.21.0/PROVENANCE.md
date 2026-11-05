# Countdown Manager 1.21.0 / 42 — exact package evidence

Source: reviewed main `42e50c61e37476cff028ba52c6e647a85edba46e`, recorded in
[source-commit.txt](source-commit.txt). Annotated tag `v1.21.0` targets that commit.
Final executable SHA-256:
`92b86a44ce612d72e56ae440eab5b12600cde1a5365221d6e715f32865f92003`.

[NativeBuildProvenance.json](NativeBuildProvenance.json) and
[NativeDesignContract.json](NativeDesignContract.json) are copied from the actual final bundle:
version/build 1.21.0/42, identifier `local.countdownmanager.app`, arm64, compiler headers SDK 15.4,
Swift 6.4, deployment/linked compatibility 13.0 and `native-calendar-graphite-v2`.
Build metadata retains `renderedAppearanceVerified: false`; runtime evidence is recorded separately.

## Package and exact runtime

[artifact-audit.json](artifact-audit.json) passed archive/feed signature and independent public-key
checks, changed-input rejection, signed-feed boundary/notes/metadata, extracted bytes/modes/symlinks
and strict/deep codesign. ZIP: 6,524,924 bytes, SHA-256
`f7e397c6f4c95d7b519c867896ee7757642d04c620b89ce8beedbb7010d25aee`.
Feed: 3,847 bytes, SHA-256
`f25af4e96b225d7cfd8c6f9a82bfbdb9546e2d6a17e3cfb43561ea3616c60f50`.
Ad-hoc app signing is not Apple notarization.

The audit predates runtime/public verification and retains its original `published`, `installed`
and `exactPackageRuntimeVerified` stage flags. The later [exact-qa.json](exact-qa.json) records
the same final executable, `productionDataUnchanged: true`, and these passes:

| Exact-package scenario | Result | Evidence |
| --- | --- | --- |
| Week creation | 4/4 | [result](week-result.txt), [manifest](week-manifest.json) |
| Ordinary editor stability | 1/1 | [result](editor-result.txt), [manifest](editor-manifest.json) |
| Native release help | 1/1 | [result](whats-new-result.txt), [manifest](whats-new-manifest.json) |

The editor [trace](editor-stability-trace.json) contains 40 zero card/title mean-RGB and geometry
deltas; [trace-summary.json](trace-summary.json) records the archival calculation. Its original
manifest still reports unsupported in-process native AX baseline inspection. [fast.log](fast.log)
and [lint.log](lint.log) retain the accepted deterministic gates and strict lint 0/96.

## Current images and limits

There are 36 PNGs: 22 week captures, six full editor captures, four editor baseline ROI diagnostics
and four release-help theme/contrast captures. The manifests list 32 full captures; ROI files are
separate diagnostics. All copies passed byte comparison, PNG CRC/decompression checks and applicable
manifest dimensions. [archive-index.json](archive-index.json) records copied-file hashes.
The three homepage images, four release-help images and selected editor/ROI drawing were visually
reviewed; passing structural checks is not a claim that every image received the same visual review.

Every scenario uses marked isolated profiles and generic demonstration events/materials.
No working-event export, private backup, user recording, fixture event JSON or application bundle
is copied into this archive. The retained manifests identify the actual 1.21.0/42 executable;
older images were not renamed as current release evidence.

`NSView.cacheDisplay` establishes local native drawing, not WindowServer compositor timing or
perceived animation smoothness. Requested sample offsets differ from recorded elapsed times.
Selected [development native-menu](../v1.20.5/week-days/PROVENANCE.md) and
[whole-application AX](../v1.20.5/editor-stability/PROVENANCE.md) external results are reused only
at their unchanged behavioural boundaries, with their original 1.20.5/41 and SDK-27 Debug identities.
They were not rerun or relabelled as exact-1.21.0 external tests. Keyboard-focus/Space delivery,
VoiceOver speech, physical status-item/Spaces behaviour, live weather and updater install/relaunch
are not established by this selected evidence set.

## Publication

[public-assets.json](public-assets.json) records publication at 2026-11-05T09:34:54Z through the
in-app browser, anonymous HTTP 200 for Latest/ZIP/versioned feed/stable feed and exact audited
payload hashes. The annotated-tag object and reviewed source were checked through the read-only
connected GitHub API after anonymous API rate limiting. The later [homepage receipt](homepage.json)
records anonymous HTTP 200 and matching default-main README/three image bytes, followed by
browser inspection of the actual page and displayed native images.
