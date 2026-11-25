# Countdown Manager 1.27.0 screenshots

These captures use the 1.27.0 / build 52 localization test bundle with isolated demonstration data.
The updater is disabled in that bundle. The executable SHA-256 is
`5b18c6f561aca3d4b75b6ba65fe966d3171a78496d9eadf80280039e610776c1`.
The build used macOS SDK 27.2, linked compatibility 13.0 and the
`native-calendar-graphite-v2` style contract.

The native scenario passed in English and Russian on macOS 27.2.1 with macOS launch languages
opposite the selected app language. Each run checked the native date field and switched language
during an open edit, preserving the draft, focus, date, timer deadline and saved bytes.

The [English desktop](desktop-en.png), [English mini-panel](mini-panel-en.png) and both Settings
captures ([English](language-settings-en.png), [Russian](language-settings-ru.png)) were visually
inspected for the README.

## Published package

The final ZIP was built from `fb0a765d23378b61c758dc9ee046820d8dc5138a`. The [package audit](artifact-audit.json)
records matching extracted bytes, modes and symlinks, independent verification of the Ed25519
archive and feed signatures, rejection of altered data and signature bytes, and the unchanged
updater key. Both packaged catalogs contain 431 localized strings. Strict/deep codesign passed.

The [release-help test](release-help-result.txt) ran on the exact extracted ZIP in a marked isolated
profile. The language and menu-bar regression tests used their separate test bundles described in
[Verification](../../VERIFICATION.md). [Public checks](publication.json) include the update URL
embedded in the installed 1.26.0. The owner can perform the actual update from that installation.
