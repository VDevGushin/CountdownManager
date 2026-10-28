# 1.19.0 / build 35 candidate evidence

Status: locally built, natively checked and signed; genuine isolated update passed. Publication
is recorded separately. All captures use newly created marked demonstration homes. No
production or user-edited preview data was used.

## Exact candidate

The canonical `build.sh` built the production-identifier bundle with the existing stable HTTPS
feed/public key. `NativeBuildProvenance.json` records compiler headers **SDK 15.4**, linked
compatibility/minimum OS **13.0**, and style **native-warm-calendar-v1**. Actual Mach-O metadata
and strict/deep signatures were verified. Version/build changes do not change style identity.

Executable SHA-256: `7ba9177241df23e6471c551728d37c0448d605fe6e60ee3511277e9f3563058c`.
The executable stayed unchanged through all three final native routes and archive preparation.
Full source/capture hashes and build provenance: [evidence.json](evidence.json).

## Final native acceptance

- [What's new 1/1](whats-new-native-result.txt): no background opening; pending import/editor
  deferral; first safe mini opening; real 430×560 content bounds; hidden mini under help;
  close/reopen and no automatic repeat; retained editor text/Cancel; re-admission when work
  appears before close; both Settings entries; unchanged event bytes and timer deadline.
- [Desktop 28/28](desktop-native-result.txt): existing sheets/editor ownership, controls,
  split/browser/details, rapid actions and shared panel state passed on this exact bundle.
- [Materials 1/1](materials-native-result.txt): durable file/link addition, unchanged source and
  owned bytes, absence of rejected Undo/status row, fixed footer/panel, collapsed mini sections.
- [Fast checks](fast-result.txt) passed on exact final sources.
  Strict SwiftLint passed with no violations. Source design gate 7/7, build contract 18/18,
  update-tool tests 12/12. No new live model eval was requested or run.

Twenty current PNGs cover the real help window and desktop/mini/editor plus the native text
composer fixture. Light/Dark × standard/Increase Contrast are represented. Help captures use
Reduce Motion; no new animation exists. The designer independently accepted the four help
renders at the same unchanged `WhatsNew.swift` source. All three sections and fixed primary
action are visible, without the rejected initial shrink/clipping.

Raw manifests: [help](whats-new-native-manifest.json), [materials](materials-native-manifest.json).
[Appearance annotations](appearance-annotations.json) distinguish the composer's local fixture
scheme from the shared global override; raw manifests are not rewritten.

## Signed package

ZIP: **6,243,670 bytes**, SHA-256
`339efbdab0e9f8ba53d30d688985f5e200c1b17c5ee436b8c603309bb68dcbaf`.
Appcast with embedded Russian instructions: **4,953 bytes**, SHA-256
`c664030aab8df972d2b7f96e811d652083d307dbe86294dd0411a35c8b4f280d`.

The existing production key signed both; its temporary seed export was deleted immediately.
[Signing receipt](signing-receipt.json). The [public-key-only audit](artifact-audit.json) validates
both signatures, rejects changed messages/signatures, checks an exactly bounded feed trailer,
matches all **168** extracted entries by bytes/modes/symlinks, and verifies deep/strict code
signatures, production configuration and native build contract. It never accesses the private key.

## Boundaries and historical failures

The first focused attempt reached panel positioning before the status item had a screen;
the fixture now waits for actual readiness. An earlier 112×274 help render was rejected despite
passing state assertions; the production layout and geometry oracle were corrected. A later
Settings transition was correctly blocked while AppKit still reported an attached sheet during
SwiftUI `onDismiss`; the one-shot request now waits for that callback to unwind and rechecks
admission. The final mini entry test also waits for mini navigation before activating its control.
These earlier attempts are not added to final PASS totals.

Cached-display PNGs are actual native rendering, not compositor/flicker or physical input proof.
The composer is a real native component fixture. Provider/history checks and internal native
actions do not certify physical cross-app drag/hover/cancel, every IME, VoiceOver, cross-Space
behavior, Intel or macOS 13 runtime. External keyboard/menu and actual Sparkle delivery need
their own evidence. Historical qualified user acceptance of materials remains separate from
the newly added help screen. No publication, production installation or user-data migration is
established by these local receipts.

The [genuine isolated update](genuine-update.json) passed download, extraction, installation and automatic relaunch with unchanged synthetic data/preferences. Its versions, payload identity, automatic discovery and independent-observer timing limits are explicit in that receipt.

The final [external Escape/Return check](keyboard-acceptance.json) passed on the new unsigned payload. The earlier genuine-update receipt is reused only for unchanged updater owners; the help-only keyboard correction and native regression are listed in evidence.json. It is not claimed as a second complete update run.
