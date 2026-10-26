# 1.18.1 / 34 evidence

All events, source files, imported copies and preferences were isolated demonstration data.
The changes are based on repository commit 81366f3. Publication status belongs in the release
document; the captures themselves do not prove publication or local installation.
[Acceptance receipt](acceptance.json) records source, image and log hashes.

- Strict SwiftLint: 0 violations in 75 files; CoreChecks/UIChecks passed.
- Native Release desktop: 27/27. [Result](native-desktop-result.txt) and
  [selected capture manifest](native-manifest.json) identify executable
  9d1750836b52666100a5bfe570dd70109bcf750b0780babb409f3fd4ac1b8814.
  Date/weather geometry was exercised with forecasts present, absent and disabled in both modes.
- External Xcode Debug: [2/2 passed](external-summary.json). These are actual key and mouse inputs
  in the existing desktop and mini-panel preview cases, with synthetic PNG, PDF and TXT files.
  The [baseline failure](baseline-summary.json) was recorded before adding keyboard shortcuts.
  The external executable has its own hash in the acceptance receipt; it is not the Release binary.

The original two desktop PNGs are native cacheDisplay renders: Light date/weather and Dark feed/details.
The two keyboard-preview PNGs are cropped XCUI screenshots of the actual presented preview
after key navigation and content clicks. They visibly include native PNG/PDF provider content.
Still images show settled layouts; external assertions establish key navigation.

Raw local reports remain under /private/tmp/countdown-1.18.1-qa, including the xcresult bundles
and the retained isolated native bundle. Local temporary paths are not durable distribution URLs.
The [production artifact audit](artifact-audit.json) separately verifies archive/feed signatures,
rejection of altered data, codesign, all 166 extracted tree entries and unchanged executable code
after removing signatures. It identifies the production executable after release configuration.
The [exact production run](native-production.json) passed 27/27 in 53.272 seconds without a stall
or executable change. Its two `release-desktop-*.png` images are the current README desktop
captures; [their manifest](release-native-manifest.json) records the production executable
15273382640c6ab3277a410ca53bc3b457bee18f41f646f91257868db09b2661 and image hashes.
Custom Quick Look extensions, every supported OS version, VoiceOver speech,
local installation and a fresh real Sparkle update were not exercised.
