# Countdown Manager 1.14.1 / 29 — production-package evidence

Captured from the exact production-configured arm64 package in
`/private/tmp/countdown-release-1.14.1.OQwJi7/qa-identity-scoped`.
Capture date: 2026-10-23, Europe/Moscow. Events and preferences are isolated synthetic fixtures.
No production event data was used as a mutable fixture and nothing was installed into `/Applications`.

## Package

- Bundle identifier: `local.countdownmanager.app`.
- Stable feed: `https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml`.
- Existing production public-key fingerprint: `327e6e5300e230c81fc087b79bb529dae667723cefd319a4c706fb57562a80b2`.
- Executable SHA-256: `a9c4fb3915e17a3ff19a9d26b457d00a8bf8520a54890dbb12117dfee7da8802`.
- ZIP SHA-256: `2acbc3fb9a61a937ddb2863418615892242db70ba9262572710372ae863383c2`.
- Appcast SHA-256: `ccf99378fc2ac46b49a8ff41a699f037d558449de923b006bc9c268b88d0301b`.
- Ad-hoc app signatures, Ed25519 archive/feed signatures and 166-entry ZIP roundtrip passed.
- Temporary private-key export was removed after signing. No permanent key backup was created.

## Acceptance

- Strict SwiftLint passed with no violations.
- CoreChecks and UIChecks passed on final sources, including direct release-cache reruns.
- Release tooling: 12 tests passed.
- Exact-package native runs: full 23/23, collapse 2/2, editor 5/5, three continuity runs 8/8 each, identity capture 2/2.
- All seven successful native results are retained beside this file.
- Manifest records 24 captures, version/build and exact executable hash.
- Four README panel captures were visually inspected in Light/Dark: compact with no favorite, featured only with a favorite, filled month-strip top, preserved tilt, no shadow and inset outline.
- Owner reviewed the isolated development preview and authorized the release.
- Earlier focused external XCUITest `testFavoriteCanBeClearedFromListAndEditor` passed. The full external XCUITest suite was not rerun for this release.

Pre-release general smoke runs exposed test-only registration/frame races. Favorite/edit
buttons now use coordinator-owned native registration; other controls retain SwiftUI
registration so offscreen checklist rows remain observable. Role-specific calendar/title
markers and settled-layout waits avoid using frames from the previous presentation.
Failed attempts were not accepted as evidence; the seven final runs above all passed.

## Limits

Contour appearance is visually reviewed, not protected by a pixel-golden assertion.
Natural diagonal antialiasing remains. Calendar Increase Contrast was not separately captured.
Physical Spaces, VoiceOver speech, older macOS, Intel and first-install Gatekeeper were not established.
Full Sparkle download/replace/relaunch was not repeated; production channel/key and signatures were verified.
Publication and anonymous-download confirmation are recorded in [publication.json](publication.json).
