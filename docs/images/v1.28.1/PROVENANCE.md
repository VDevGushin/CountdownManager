# Countdown Manager 1.28.1 screenshots

The README screenshots were captured on 28 November 2026 from Countdown Manager 1.28.1 (54) with an
isolated profile and demonstration data. The production update configuration and native build
route were used. The Records scenario passed 4/4.

| Image | Surface | Appearance | Pixels |
| --- | --- | --- | --- |
| desktop-records-dark.png | Desktop window | Graphite | 2240 × 1496 |
| mini-records-light.png | Mini-panel | Light | 780 × 1200 |

The build uses native-calendar-graphite-v2, macOS SDK 27.2 and linked compatibility 13.0.
The capture executable SHA-256 is c90818f842a8d31d360c2673b70a0cb1eb55743d621d401ba41378c8d7205956.

The screenshots use NSView.cacheDisplay. The fixture also includes Light, Dark and Dark
Increase Contrast states on both surfaces.

## Final package verification

- The reviewed fix is `605391a36ef01a356764d3fcc624bd636d765644`. Independent review reproduced
  malformed-reference normalization during review. The corrected code accepts authentic
  references and rejects corrupted IDs before copying, even when Foundation can resolve them
  to an existing pathname.
- External product QA used Finder gestures on macOS 27.2.1. ZIP dropped onto an unselected event
  and PDF onto an unselected record. Both saved the right identity, original name and exact bytes.
  Folder, package and symlink attempts wrote no attachments. A following unknown-type file
  succeeded and survived a restart. Native Records and stress routes passed 4/4 and 6/6.
- The signed archive executable SHA-256 is `fa54fc25febaa088da1ded7d74daf53b1bf93a9bd102166b8498c261a0ce329f`. The app extracted from
  the audited ZIP reproduced both README PNGs byte for byte. It passed the Records route,
  Russian and English release help, and two actual Finder gesture XCUITests into Events and Records.
  The English release-help run timed out after synthetic back-to-back status-item presses on its
  first attempt and passed on a fresh isolated profile.
- Direct cross-app gestures into the mini-panel, into an open editor, and from Safari did not
  reach the application in the extended test driver. Shared routes passed native and fast checks.
  The release verification does not cover macOS 13 runtime or the owner's final installation.
- [Package audit](artifact-audit.json), [public verification](publication.json) and
  [handoff](handoff.json) record the signed publisher assets and local handoff.
