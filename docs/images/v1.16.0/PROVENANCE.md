# Countdown Manager 1.16.0 / build 31 — candidate evidence

Date: 2026-10-24. Status: **PREPARED LOCALLY / NOT PUBLISHED — RC2**.
The latest published release remains [1.15.0](../../releases/v1.15.0.md).
The candidate is prepared locally; this document does not record publication or installation in `/Applications`.

## Exact bundle and captures

Version **1.16.0**, build **31**, identifier `local.countdownmanager.app`, arm64, **RC2**.
Executable SHA-256: `cb2723661e394f1a9e0de09349fde688b2f40bf4d9c83ad0a184fab023d401e4`.
The local candidate receipt records production configuration and deep/strict codesign verification.

[manifest.json](manifest.json) lists **27 selected PNGs**, their SHA-256 values, dimensions,
appearances and the same executable hash. They were copied from the exact candidate's native
desktop run; the complete local RC2 run contains 84 PNGs. The original manifest digest is
`f70cba7082c33cf76926ff4377a37b79958cc736f671e6cf95ef5e2b8e728e62`.
The selected captures use `NSView.cacheDisplay` and synthetic events, local files and forecasts.
They are in-process native renders, not compositor screenshots, videos or physical-input evidence.

Local RC2 candidate/evidence root: `/private/tmp/countdown-1.16.0-rc2.joYRN1/`.
The original native routes and their run receipts remain in `native-desktop-previews-aqua`,
`native-mini-previews-aqua` and `native-editor-previews-aqua` beneath that root.

## Automated native acceptance

The [acceptance receipt](acceptance.json) records strict SwiftLint with **zero violations in 70 files**
and **PASS** for CoreChecks/UIChecks, separately from the native routes and reused workflows.

The exact production candidate passed in the Aqua session:

- Desktop: **27/27** (40.143 s).
- Mini-panel: **23/23** (28.606 s).
- Shared editor workflows: **5/5** (9.116 s).

Each route records launch exit 0 and an unchanged before/after executable hash matching above.
Desktop coverage includes real PNG/PDF/movie thumbnail generation and corrupt-file fallback,
0/4/5/15 attachments, four/all/collapse, selection reset, 44-point preview geometry, unchanged
compact rows, actual compact filename/size alignment in 18-point symbol columns across file types,
shared Save/Cancel and copy removal, indicator/progress coexistence, plus inline
overview weather with stable loaded/off geometry in narrow/wide collection and feed layouts.
These are native in-process assertions, not proof of all external interactions.

An earlier **RC1** restricted launch is retained separately at the RC1 evidence root
`/private/tmp/countdown-1.16.0-rc.Tg2pkY/native-desktop-previews/run-receipt.json`:
launch exit **1**, no scenario results. Its launcher reported LaunchServices **-10827**
(`kLSNoExecutableErr`). It is a failed launch, not a passed test or evidence that the inspected
executable was absent. The later Aqua RC1 run used its same executable hash
`5b808ef91c3bbd912a56ccbefbf4c69f84f59220e37271bfa987ff05cc817a19` and passed **26/26**;
neither receipt is a result for the final RC2 hash. Both are preserved separately.

The earlier external attachment picker/Save/Cancel scenario passed **1/1** on English input for
the preceding working build. Its [original provenance](../v1.15.0/attachments-header-unreleased/PROVENANCE.md)
is preserved; it is reused evidence for unchanged flows, not a new external run on 1.16.0/31.

## Independent visual review

The visual review covers seventeen selected images: four/all/last attachment previews in both appearances,
collection/feed attachment indicators in both appearances, the two compact panels and loaded
overview weather, plus editor/mini mixed-type alignment in both appearances.
Ten unchanged PNGs were verified byte-identical to the independently reviewed RC1 captures;
the three changed captures and four new alignment captures were inspected from RC2.
No actionable clipping, overlap or unreadable control was found. Compact PDF/image/movie/text
filenames and size lines begin at the same horizontal position, including two-line names.
The movie's film marker, type fallback, plain accent disclosure, four-row collapsed list and
the final file with `Свернуть` are visible. Two-line long names remain readable. Compact panels
retain symbols and file opening without a duplicate editing button.

The preview fixture shows a wide details pane. Narrow-pane indicator coexistence is visible;
these selected images alone do not establish thumbnail text layout at every details-pane width.
The synthetic PDF is a two-page color fixture; its red first-page thumbnail is evidence of page
selection, not a real personal document. Synthetic images/video also use simple color patterns.

## Local archive audit

The independent public-key-only audit records:

- Archive RC2 `CountdownManager-1.16.0-31.zip`: **5,639,648 bytes**,
  SHA-256 `765f50a7ce2c7a35945ca8793fc776dec7f67bdc4f83e61958b6d0ba8b71e47a`.
- Signed appcast RC2 SHA-256: `4a387e1add8488a1847dc9f02661e68e05ea1bce41074770fc56f9654747c5ff`.
- Archive/feed Ed25519 signatures verified through Apple CryptoKit using only the public key;
  damaged messages and damaged signatures were rejected.
- Production public-key fingerprint matches the published baseline; no test flags or loopback exemptions.
- Extracted app deep/strict codesign passed; **166** tree entries match the candidate, including symlinks and permissions.

[artifact-audit.json](artifact-audit.json) records the final RC2 results. The original audit and
signature receipts remain under the local RC2 evidence root's `production-audit/`.
No auditor access to the private key or public upload is recorded by that audit.

## Genuine isolated update

The [RC1 actual-update receipt](genuine-update-rc1.json) records **PASS** for 1.15.0/build 30 → 1.16.0/build 31 **RC1** through Download
and Install and Relaunch. Old PID `88845` was replaced by automatic PID `89211` at the same app
path, observed before any manual reopening. Two synthetic events, checklist/favorite state,
the exact JSON bytes and isolated dark preference were preserved.

The fixture derives from the genuine published baseline host
`d7486a2ac7f394b794cad2463bce60a4ff261e9e80e23a0eb4eae9e2dd4eb25d`
and the RC1 production candidate hash
`5b808ef91c3bbd912a56ccbefbf4c69f84f59220e37271bfa987ff05cc817a19`.
It uses an embedded isolated home, local HTTP and a disposable test key.
The receipt confirms unchanged unsigned RC1 code in that test fixture;
the reconfigured/resigned updated test host has hash
`3f1a6d5c1d8929a211cc5a5f8b86ecb7719e3b901304c05256c1e1e7f2640e60`,
which is distinct from both production-candidate host hashes. Production app/data were not modified.
Original receipt: `/private/tmp/countdown-1.16.0-update._u59l5ib/fixture/actual-update.json`.

Only the compact 18-point icon column and its measurement hooks changed afterwards for RC2.
The update receipt is reused pipeline evidence, not a new upgrade run on RC2. It establishes
the actual guarded replacement/relaunch workflow on isolated test copies, not production-feed
publication, anonymous HTTPS access or first-install acceptance.

## External media opening

The [RC1 media receipt](media-acceptance-rc1.json) records native multi-file picker import/Save
for three synthetic files: PDF (660 bytes), MP4 (41,999,406 bytes) and PNG (264,650 bytes).
Source/copy SHA-256 values match, each copy is distinct from its original, and originals remain unchanged.
PDF and PNG were opened from Countdown's saved copies in Preview. The MP4 copy was played in
QuickTime through 15.958 s after a manual retry. Initial cold video-row opening from Countdown
was inconclusive; manual retry is not represented as proof of reliable cold default-application opening.
A later warm row action in Countdown opened the owned copy in QuickTime, without autoplay.
After full Quit/relaunch the mini-panel showed all three saved files; JSON bytes and copy hashes
were unchanged. RC2 subsequently changed only compact label geometry and measurement hooks;
this is explicitly reused RC1 workflow evidence, not a fresh external media run on RC2.

## Remaining acceptance limits

Cold first-launch default-app opening remains uncertified. Mid-copy cancellation was not forced
on the fast filesystem; code/native cancellation assertions are not a substitute for that physical timing case.
Prepared signed artifacts do not establish public download availability. Release status is tracked in
[v1.16.0.md](../../releases/v1.16.0.md).

No full VoiceOver speech, all filename/count extremes, large-media performance, every codec,
physical Spaces/multiple displays, older macOS, Intel or Gatekeeper-first-install claim follows
from these renders. Previous release images and working-source provenance remain unchanged.
Raw external screenshots containing the surrounding personal desktop are not included here.
