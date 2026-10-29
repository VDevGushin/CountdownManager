# Countdown Manager 1.20.1/37 — production release evidence

Status: published as Latest on 2026-10-29; exact-package acceptance and anonymous delivery passed.
[Publication receipt](publication.json) records the source commit/tag and three HTTP 200 downloads
matching the independently audited sizes and hashes.

Seven fresh PNGs show the exact production app on isolated synthetic data. Native rendering uses
NSView.cacheDisplay, not an external compositor recording. The manifest binds PNG hashes to the
executable. The native receipt records desktop **31/31** and help **1/1**, unchanged executable and no
recorded ui.stall. Source gates, full lint and current CoreChecks/UIChecks passed; the final source
and build-contract gates were repeated after DESIGN documentation was frozen. An initial packaging
attempt was correctly rejected because DESIGN changed while it was building; no stale bundle shipped.

The selected `desktop-settings-light.png` and Dark companion come from the isolated native
fixture, where update checks are intentionally disabled. Its channel-not-configured message is a
fixture condition, not the production bundle configuration. The README therefore shows the
current release-help and event feed images; the Settings images remain in this evidence set.

The public-key-only artifact audit validates ZIP/feed signatures and changed-byte/signature
rejection, exact unique feed trailer, embedded patch instructions/workaround, all **168** extracted
entries, nested strict/deep codesign and production/build configuration. The signing receipt
confirms the existing production key and deletion of its temporary seed export.

The earlier genuine fixed-source update from build **20120 → 20121** remains valid evidence of the
unchanged sheet-termination mechanism; it is separately labelled and is not a new public
1.20.0 → 1.20.1 install. The host executing that first public upgrade is still the old app: use mini
Settings or close desktop Settings before Install. See the [bug protocol](../../qa/desktop-update-restart-2026-10-29.md).

No production installation is part of this release task. Existing /Applications app is left for the
user to update. External XCTest was previously unavailable at automation initialization; this release
does not claim a successful new XCTest run. See [release status](../../releases/v1.20.1.md).

Temporary build/cache/signing helpers and the local candidate were moved to recoverable Trash after
publication. [Cleanup receipt](cleanup.json) records the restore manifest. The installed app was not
updated by the agent; its executable remained unchanged during cleanup.
