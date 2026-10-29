# 1.20.3/39 native evidence

All final retained native images below come from the production-configured ZIP's exact executable:
`e63028be6702cea4e6a0f140d7069a53fb352a60463caf8e5b2ede6247804abe`.
Built through `build.sh` with headers SDK 15.4 and linked compatibility 13.0, the existing feed and
production public key; no subsequent reconfiguration or re-signing.

- [Panel manifest](panel/manifest.json): 31 PNGs, running/finished glyph guard passed.
  [Panel result](verification-panel.txt): **5/5**.
- [Desktop receipt](native-desktop.json): **31/31**, 131 runtime images, five selected images
  retained here, including the README's Graphite feed and Light collection.
  [Desktop result](verification-desktop.txt).
- [Release-help manifest](help/manifest.json): four Light/Dark/contrast PNGs, **1/1**.
  [Help result](verification-help.txt).
- [Final deterministic checks](verification-fast.txt) and
  [documentation reference audit](documentation-audit.json).

README's `timer-running-strip.png` is the top 780 × 120 pixels of `panel/03-timer-running.png`.
`timer-finished-strip.png` comes from `panel/05-timer-finished.png` in the same way. No resizing or
retouching; README displays the running strip at 390 × 60 points. Running, finished, dark feed,
light collection, retained mini-panel and dark release-help images were visually inspected.
Fixtures are synthetic, including injected civil dates in the retention scenario; no production
content appears in these images.

The owner also accepted a live isolated candidate screenshot at 00:46 Moscow time on 2026-10-30.
That earlier candidate had the same glyph correction but preceded a release-help wording change;
it is not presented as the final ZIP hash. The final package was then checked above.

The first exact-panel attempt overlapped the desktop test and failed native editor focus.
Desktop passed; a sequential panel repeat passed, followed by release help. Earlier general
mini-panel evidence is [retained separately](verification-native.txt) and was intentionally reused
for unaffected flows rather than called an exact final-executable run.

[Final package audit](artifact-audit.json) records signed ZIP/feed hashes and public-key checks.
Screenshots establish layout and these fixture scenarios; external keyboard, VoiceOver, every
Quick Look provider and older macOS releases are not certified by them.
