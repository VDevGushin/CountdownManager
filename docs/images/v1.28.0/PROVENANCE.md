# Countdown Manager 1.28.0 screenshots

The two README images were captured on 28 November 2026 from the native release build
of Countdown Manager 1.28.0 (53) using an isolated profile with demonstration events and
records. The app was built with `build.sh` in release update mode and launched with
`--ui-smoke-desktop --ui-smoke-records`. The run passed 4/4.

| Image | Surface | Appearance | Pixels |
| --- | --- | --- | --- |
| `desktop-records-dark.png` | Desktop window | Graphite | 2240 × 1496 |
| `mini-records-light.png` | Mini-panel | Light | 780 × 1200 |

Style `native-calendar-graphite-v2`, macOS SDK 27.2, linked compatibility 13.0.
The published executable SHA-256 is `b1b5cb0836bf85fe3e995949226f51ed98fa665c201694cf2220b476c7ac3b09`. Repeating the native capture
scenario on that executable produced both README PNGs byte for byte.

The screenshots use `NSView.cacheDisplay`. The checked native fixture also includes
Light, Dark and Dark Increase Contrast states on both surfaces.

## Final package verification

- [Package audit](artifact-audit.json) verifies both Ed25519 signatures, mutated-input
  rejection, strict bundle signing and identical bundle bytes, modes and symlinks after extraction.
- On macOS 27.2.1 the final executable passed Records 4/4 and the Records stress sequence 6/6.
  The fixture covered checklist reordering across both surfaces, file/link/text intake,
  scoped search, deletion and preservation of data on Cancel or rejection.
- The focused native What's New scenario passed in Russian and English. Intermittent earlier
  in-process presses timed out before the window appeared. In a separate XCUITest on the
  extracted release ZIP, the English window appeared once, pointer clicks on the macOS status item closed
  and reopened the mini-panel three times with the timer running, and Settings reopened
  What's New. The timing of an immediate synthetic double press remains intermittent.
- [Public verification](publication.json) verifies anonymous downloads, the tag and the
  rendered README images. [Handoff](handoff.json) identifies the previous app left running for
  the owner's manual installation.
