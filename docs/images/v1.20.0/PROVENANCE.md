# Countdown Manager 1.20.0/36 — production candidate evidence

Status: local acceptance passed; publication pending.

These are fresh native captures from the exact production bundle, using isolated synthetic events,
preferences and copied files. Historical retention images from the 1.18.1 development base are not
reused as proof of this integrated release. 1.19.0 links, drag-and-drop, text intake, guides and
native help are preserved. The release uses the established SDK 15.4 build contract.

The native [production receipt](native-production.json) records desktop 30/30, mini 23/23,
editor 5/5, materials 1/1 and highlights 1/1, with the executable unchanged and no recorded ui.stall.
[Manifest](manifest.json) binds 12 selected PNGs to the bundle executable and PNG SHA-256 hashes.
Images are NSView.cacheDisplay native renders, not compositor recordings or proof of no flicker.

[Signed-artifact audit](artifact-audit.json) independently validates public-key signatures,
changed-message/signature rejection, embedded update notes, bounded feed trailer, all 168 extracted
bytes/modes/symlinks, strict/deep signatures and production configuration. The
[signing receipt](signing-receipt.json) confirms unchanged production key and deleted temporary seed.

[Fast gate](fast.log), [lint](lint.log) and [update-tool checks](update-tools.log) are current-source
results. The earlier external XCTest runner timed out before any test; the development-stage direct
native UI fallback is separate evidence and does not replace external automated confirmation.
A real 1.19.0 → 1.20.0 Sparkle installation has not been exercised by this release task.

See [release status](../../releases/v1.20.0.md). Public delivery is recorded only after publication.
