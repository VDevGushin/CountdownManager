# Countdown Manager 1.16.0 / build 31 — priority and attachment-limit evidence

Date: 2026-10-24/25, Europe/Moscow. Status: **PREPARED LOCALLY / NOT PUBLISHED**.
This follow-up replaces the locally prepared RC2; its [historical evidence](../PROVENANCE.md)
is preserved. The [release record](../../../releases/v1.16.0.md) distinguishes preparation
from publication and installation in `/Applications`.

## Exact bundle and captures

Version **1.16.0**, build **31**, identifier `local.countdownmanager.app`, arm64.
Executable SHA-256: `6cd3c5979e12ebf518e334d7bf7e7547cbe9c267087ca18665fe9e9a46cca9bf`.
The local candidate receipt confirms production configuration and strict/deep codesign.

[manifest.json](manifest.json) records **39 selected native PNGs**, their dimensions,
appearance metadata and SHA-256 values. The complete desktop run contains 100 PNGs;
its source-manifest digest is
`735920ec81e1ab97a3eedaa460e20262fbc559f1606fa1447b51fe61433b9889`.
All captures use isolated synthetic events, files and forecasts. Capture method is
`NSView.cacheDisplay`: in-process native rendering, not compositor screenshots or physical-input evidence.

Local evidence root: `/private/tmp/countdown-priority-limit.Tdj3Jx/`.
The exact candidate is `candidate/Countdown Manager.app`; original route receipts remain in
`native-desktop-previews-accepted-aqua`, `native-mini-previews-accepted-aqua` and
`native-editor-previews-accepted-aqua` beneath that root.

## Fresh acceptance

The [acceptance receipt](acceptance.json) identifies the final checks and reused historical evidence.
Strict SwiftLint reports **0 violations in 70 files**; CoreChecks/UIChecks report **PASS**.
Fresh exact-bundle Aqua routes passed:

- Desktop: **27/27**, 42.748 seconds.
- Mini-panel: **23/23**, 28.017 seconds.
- Shared editor: **5/5**, 9.204 seconds.

Every route exited 0 with unchanged before/after executable hashes matching the candidate above;
no main-thread stall was reported. Desktop coverage includes the shared desktop/mini attachment
flows: note → subtasks → files, matching headings, hidden empty sections, 0/3/4/15 files,
44-point desktop and 36-point mini thumbnails, first-four summaries, separate bounded libraries,
filename search/clear/no-results, Back and owner-removal cleanup. The editor is checked at 15/15,
then removal to 14 re-enables Add; Cancel retains the fifteen saved files. A missing owned copy
reports a foreground error. Saved lists omit the expiry footnote, which remains in editor/delete UI.
Core/Store checks cover rejection of oversized batches before copying and preservation of seventeen
historical owned copies through load, unrelated Save and repository reload.

Two earlier desktop runs are retained as **FAIL**, separately from final PASS:
`native-desktop-previews-aqua` and `native-desktop-previews-final-aqua`. Their driver required
registry destruction after Back/Cancel while it retained the captured NSWindow itself.
The corrected predicates observe detached, hidden sheets and restored interactive owners;
internal mini-screen removal still requires registry cleanup. Observation receipts preserve
the retained-window state. These corrections are driver criteria, not changes to product Back/Cancel behavior.

## Visual review

The current native-QA receipt records visual inspection of eleven selected renders covering both
appearances, editor limit/order, overflow error, mini thumbnails, bounded libraries/search/empty
results, missing-copy error and the saved surface without an expiry footnote. The preceding
design review independently inspected twelve new renders. No actionable visual issue was reported.
These selected renders do not establish every possible filename, codec, screen width or transition frame.

## Local signed-artifact audit

[artifact-audit.json](artifact-audit.json) records an independent public-key-only CryptoKit audit:

- ZIP `CountdownManager-1.16.0-31.zip`: **5,754,463 bytes**, SHA-256
  `477c9cbf208ddfea53dc984e7447f82002bde4094cc4ef2265acb5b9a7fc70f4`.
- Signed appcast SHA-256: `0af6a8c17bbfa5e169e82447196f0320d78ffc9a6ffd74da6c203818696585a0`.
- Both Ed25519 signatures pass; damaged messages and signatures are rejected.
- The production public key/channel matches the published baseline; no test flags or loopback exemptions.
- Extracted strict/deep codesign passes; all **166** tree entries, symlinks and modes match the candidate.

The auditor did not access the private key or publish artifacts. Prepared files do not prove
public download availability, first installation or production update acceptance.

## Reused evidence and remaining limits

The [genuine isolated update](../genuine-update-rc1.json) and [media/restart receipt](../media-acceptance-rc1.json)
belong to RC1 executable `5b808ef91c3bbd912a56ccbefbf4c69f84f59220e37271bfa987ff05cc817a19`.
They are reused only for unchanged updater, storage and external-opening paths; neither is a new
run on this follow-up. The update fixture used a disposable test key, local HTTP and isolated home.
The [earlier external picker/Save/Cancel run](../../v1.15.0/attachments-header-unreleased/PROVENANCE.md)
is separately identified as a 1/1 result on English input, not a fresh physical-picker test of this bundle.

Cold first-launch default-app opening and forced mid-copy cancellation remain uncertified.
Older macOS, Intel, first-install Gatekeeper, physical Spaces/multiple displays and full VoiceOver
speech need separate evidence. Synthetic thumbnail/media fixtures do not prove every codec or
large-media performance. Production events are not used as mutable QA fixtures.
