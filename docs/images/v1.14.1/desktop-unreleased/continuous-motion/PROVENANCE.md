# Continuous desktop motion evidence

2026-10-23, unreleased `codex/desktop-window`, package 1.14.1/29. No release is implied.

## Native settled images

Source: `/private/tmp/countdown-motion-fix/actual-native/Captures`.
Release executable SHA-256: `b4e5a19c7041b5d0613134c474b9ba6c7d1d9733a2fc6dadee5c4a63649c1a9f`.
The exact manifest, 44 synthetic native PNGs and PASS 20/20 result are retained. PNG file coverage,
signatures and dimensions are checked against the manifest. README images are current settled
collection Dark, feed Light, confirmation Light and settings Dark. Historical images are preserved.
These `NSView.cacheDisplay` renders do not establish compositor animation.

## Actual compositor recording

`desktop-transition.mp4`, `compositor-forward.jpg`, `compositor-reverse.jpg` and source timestamps
come from `/private/tmp/countdown-motion-review/ActualLayoutMotion.xcresult`.
Debug executable SHA-256: `765cf7bfc8755c8cf297e3f72c0b9bd24a34879624b474e81e29d8fb04b0faef`.
The focused XCUITest passed 1/1 with zero failures/expected failures. Its UI source matches the
Release build, but the binaries are different configurations and are not presented as identical.

The video is cropped strictly inside the synthetic app browser, with no other desktop content.
It preserves real movement rather than generating interpolated frames. Original raw recordings
and failed experimental iterations remain private under `/private/tmp`, not published here.
Source frames show actual motion in both directions, without blank text or scrambled glyphs.
Temporary card occlusion and label crossings remain; no collision-free or 60-fps claim is made.
See the [focused report](../../../../qa/desktop-continuous-motion-2026-10-23.md).
