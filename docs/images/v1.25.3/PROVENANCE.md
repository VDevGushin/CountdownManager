# Countdown Manager 1.25.3 package verification

The frozen main source is `44635f66b0a9f818c637e3b071d5b137e17416a6`.
The [package audit](artifact-audit.json) records the executable, ZIP and appcast hashes.
CryptoKit accepted the archive signature and the exact signed appcast bytes and rejected
altered payloads and signatures. The ZIP extraction matched file bytes, modes and symlinks.
Strict and deep codesign verification passed. The app bundle is signed ad hoc.

[Verification results](verification.txt) include strict SwiftLint, both native design suites,
CoreChecks, UIChecks and three external XCUITests on the exact extracted app on macOS 27.2.1.
External tests exercised status-item clicks, Finder dismissal, and the return from the
desktop to the mini-panel with both Mars and a static event label. The
[compositor captures](status-item-ui.json) show the highlight while open and its removal when closed.
The isolated native smoke exercised the animation and immediate transitions with Reduce Motion.
Physical clicks inside the transition interval and switching to a separate macOS Space
were outside the confirmed external coverage. The release package was exercised on macOS 27.2.1.

The [desktop](desktop-title-alignment-manifest.json), [mini-panel](mini-panel-manifest.json)
and [release help](whats-new-manifest.json) captures use isolated demonstration data and
the same extracted executable. Both homepage images were visually inspected.
