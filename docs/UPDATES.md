# Preparing signed updates

Release **1.16.0 / build 31 is published as Latest; anonymous ZIP and appcasts are verified**. It includes task-first
ordering, a 15-file cap, 36-point mini previews and separate searchable file libraries.
The current desktop library uses the same native SwiftUI sheet as Settings and the editor,
with a right-side close button and parent-content outside-click dismissal. Mini Back matches Settings; both surfaces keep counts only in the footer.
The current follow-up also removes duplicate saved-section editor links; the event header
pencil is the sole editor entry. All three desktop routes share native sheet appearance and
system animation; macOS owns timing and Reduce Motion. Route ownership persists until native
onDismiss. Editor drafts still require Save/Cancel, and a nested diagnostic Save panel retains
Settings. Shared editor rows now have 36-point previews before Save and after reopening; every
format requests a best-effort native preview, with a fallback when unavailable. Mini attachment disclosure
keeps heading/count positions fixed. Ordinary feed rows use top-aligned calendar/title,
upper-right remaining time, date/weather in one line and horizontal checklist/file summaries;
ordinary grid/details retain their layout. The featured favorite places date/weather inline
on a full-width row below its title/calendar identity, preserving room in narrow panes.
The exact `5f88a554429be8ff9aae44036ef377cd9623c7a0cd4c439eee3ab1745f716254` bundle passed
native desktop **27/27** in **52.034 seconds**, exit 0, unchanged executable and no stall/timeout;
strict lint reports **0/71** and final CoreChecks/UIChecks passed with exit 0.
[Current native-sheet provenance](images/v1.16.0/native-sheets/PROVENANCE.md) identifies
42 selected images from 110 native PNGs and the separate physical-click platform probe.
These are not a new full mini/editor suite or a compositor-animation recording.
A fresh genuine isolated **1.15.0/30 → final 1.16.0/31** Sparkle update passed Download,
Install and Relaunch: old PID 19194 became automatically relaunched PID 19340 at the same
application path, with unchanged synthetic JSON (two events, checklist and favorite) and
preserved Dark preference. [Final update receipt](images/v1.16.0/native-sheets/genuine-update-final.json)
and [payload isolation](images/v1.16.0/native-sheets/genuine-update-payload-isolation.json)
identify separate test IDs, a marked isolated home and unchanged unsigned production code.
The disposable test key and local HTTP are separate from production signing/public HTTPS;
[local downloads](images/v1.16.0/native-sheets/genuine-update-local-downloads.json) match test artifacts.
The [first attempt](images/v1.16.0/native-sheets/genuine-update-first-attempt-failure.json)
remains FAIL because two host processes were observed; the cause is unresolved. The accepted
repeat omitted all UI state reads or application reacquisition between the final Install click
and independent relaunch observation and found one host process. This does not certify first
installation, old macOS, Intel or public HTTPS availability.
The previous `69c29794…` candidate passed native
desktop **27/27** (55.659 seconds, exit 0, unchanged executable, no stall/timeout) and strict
lint **0/70**; final CoreChecks/UIChecks also passed with exit 0.
[Historical desktop-polish acceptance](images/v1.16.0/desktop-polish/acceptance.json) retains exact origins and limits.
[Historical desktop-polish provenance](images/v1.16.0/desktop-polish/PROVENANCE.md) identifies
54 selected/124 full native images and the [historical public-only artifact audit](images/v1.16.0/desktop-polish/artifact-audit.json).
Cache-render observation times exceeded requested motion offsets; no new first-200-ms
compositor-fluency or full mini/editor-suite claim is made for this executable.
The preceding exact `5836d970…` candidate passed strict lint (0/70), CoreChecks/UIChecks, native desktop
27/27, mini 23/23 and a public-key-only signed-artifact audit.
[Previous overlay provenance](images/v1.16.0/attachment-overlay/PROVENANCE.md) records 17 new
native images and exact bundle/artifact hashes. Scoped external CUA acceptance also passed
inside/outside/cross/Escape dismissal and mini Back/search/clear on an isolated probe with
identical unsigned code; it is recorded in the [overlay receipt](images/v1.16.0/attachment-overlay/acceptance.json).
The preceding
[priority/limit candidate](images/v1.16.0/priority-limit/PROVENANCE.md) remains historical evidence.

Previous RC2 signing/archive audit and native routes are retained historical evidence;
they do not certify the follow-up. RC2 desktop/mini/editor routes passed 27/27, 23/23 and 5/5. Genuine isolated
1.15.0-to-1.16.0 RC1 install/relaunch passed with a disposable test key and local HTTP; that is
reused pipeline evidence, not a new upgrade run for RC2 or production HTTPS publication.
RC1 PDF/PNG opening in Preview, warm movie-row opening in QuickTime, playback and full restart
passed; these unchanged storage/opening workflows are reused with their RC1 origin stated. Cold first-launch default-app opening
remains explicitly uncertified. The [priority/limit acceptance receipt](images/v1.16.0/priority-limit/acceptance.json)
separates fresh follow-up gates from reused RC1 workflows; the [RC2 receipt](images/v1.16.0/acceptance.json)
remains historical evidence.
Anonymous ZIP, version-specific appcast and stable Latest appcast returned HTTP 200 and
match the signed local SHA-256 values. The stable feed contains 1.16.0/build 31 and the expected
enclosure. Latest is confirmed by the anonymous public HTTPS redirect and browser badge;
the anonymous API was rate-limited with 403. No authorization or cookies were used.
[Publication receipt](images/v1.16.0/native-sheets/publication.json) identifies source commit
`91b20285f2a1983021357b0bf624e6dd5bd787db` and tag `v1.16.0`.
Preparation receipts below retain their original statuses and timestamps.
Final artifact hashes and release status: [releases/v1.16.0.md](releases/v1.16.0.md).

Previous release **1.15.0 / build 30 was published as Latest** and added the native desktop window alongside
the menu-bar panel. Signed ZIP/feed, public-key-only audit, external input, diagnostic Save and
genuine isolated older-to-newer updater acceptance passed. Anonymous archive, version-feed and
stable-feed downloads returned HTTP 200 and match the signed artifacts.
Published status: [releases/v1.15.0.md](releases/v1.15.0.md).

Previous release **1.14.1 / build 29** was published as Latest with the existing production key and stable feed.
Only the explicit favorite receives the large card. Calendar month strips fill the top edge;
tilt remains, shadows are removed and outlines are inset. Publication status and final evidence
are tracked in [releases/v1.14.1.md](releases/v1.14.1.md). Anonymous archive, version feed and
Latest feed downloads returned HTTP 200 and matched the locally signed SHA-256 values.

Previous release **1.14.0 / build 28** was published as Latest with the existing production key
and stable feed. Anonymous archive/version-feed/Latest-feed downloads returned HTTP 200
and matched the locally signed SHA-256 values. Automatic/custom event title mode now survives Save and restart; legacy events
remain custom. The exact production bundle passed seven isolated native scenarios and produced
six fresh editor captures. Core/UI regressions include negative reset/validation/deletion cases,
768 seeded actions and eight overlapping-write outcomes. See [releases/v1.14.0.md](releases/v1.14.0.md).

An earlier published release is **1.13.5 / build 27**. Its branded Default/Dark icon and
terracotta menu stripe are retained. Evidence remains in [releases/v1.13.5.md](releases/v1.13.5.md).

Previous release **1.13.4 / build 26** introduced the terracotta menu-bar stripe.
Its evidence remains in [releases/v1.13.4.md](releases/v1.13.4.md).

## Channel and signing key

The selected stable feed is
`https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml`.
The current published version-specific archive URL is
`https://github.com/VDevGushin/CountdownManager/releases/download/v1.16.0/CountdownManager-1.16.0-31.zip`.
The signed `appcast.xml` and ZIP are published together as Latest; anonymous downloads match
the locally signed SHA-256 values. Keep the canonical stable feed above unchanged for future releases.
Keep archive URLs tied to their version tags; keep the
bundle's feed URL stable. GitHub Pages is an alternative host, not required for this chosen path.
A private repository does not automatically provide anonymous downloads. Never embed access
tokens or private-feed credentials in the application.

According to the local key-setup receipt dated 2026-10-12, the production Ed25519 key was created
in login Keychain under account **`local.countdownmanager.app.sparkle.production`**, service
`https://sparkle-project.org`. Reuse this account for subsequent releases; do not generate a
replacement key for each version or accidentally use Sparkle's default `ed25519` account.
Its public-key fingerprint is SHA256 of the decoded 32-byte key:
`327e6e5300e230c81fc087b79bb529dae667723cefd319a4c706fb57562a80b2`.

After resolving the pinned Sparkle dependency, retrieve only the existing public key:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account local.countdownmanager.app.sparkle.production -p
```

`-p` prints only the public key and fails if the named key is absent. Only that base64 32-byte
public key belongs in the bundle. Never print, commit, upload or ship the private seed.
The release tool currently accepts a protected seed file via `--private-key <file>` and checks
that it matches the embedded public key. No Apple credentials are needed.

The key-setup receipt records that **no permanent backup was created**. A future permanent backup
must be a separate deliberate export
to a protected location chosen by the user, outside the repository, release output and hosting
server. Restrict its permissions to 0600 or stricter. These instructions are not evidence that
a backup has been made.

Ad-hoc signatures do not provide Apple notarization. First-install Gatekeeper trust remains
separate from Sparkle's archive/feed authenticity. Both signed feeds and verification before
archive extraction are required; signature-failure fallback expiration is disabled. Losing the
production key will require a manually installed recovery version; do not promise automatic
key rotation without a Developer ID trust path.

## Build and prepare a release

The default `./build.sh` makes a development bundle with the updater disabled.
To explicitly configure and prepare a release, reuse the named Keychain account. The following
workflow uses Sparkle 2.10.0's verified `generate_keys --account … -p` and `-x <file>` options.
`-x` requires a nonexistent destination file; it exports the existing key rather than creating
a new one. The subshell's restrictive umask protects the temporary export from creation, and
the exit trap deletes it after signing or on failure. Do not enable shell tracing or inspect
the seed contents. Running these commands does not create a permanent backup:

```sh
(
  set -euo pipefail
  umask 077
  sparkle_tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
  key_account='local.countdownmanager.app.sparkle.production'
  production_public_key="$("$sparkle_tools/generate_keys" --account "$key_account" -p)"
  work_dir=$(mktemp -d /private/tmp/countdown-release-build.XXXXXX)

  COUNTDOWN_UPDATE_MODE=release \
  COUNTDOWN_UPDATE_FEED_URL='https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml' \
  COUNTDOWN_UPDATE_PUBLIC_KEY="$production_public_key" \
  COUNTDOWN_VERSION=1.16.0 COUNTDOWN_BUILD_NUMBER=31 \
  APP_OUTPUT_PATH="$work_dir/Countdown Manager.app" ./build.sh

  signing_dir=$(mktemp -d /private/tmp/countdown-release-signing.XXXXXX)
  trap 'rm -f -- "$signing_dir/private-seed"; rmdir -- "$signing_dir"' EXIT
  "$sparkle_tools/generate_keys" --account "$key_account" -x "$signing_dir/private-seed"
  chmod 600 "$signing_dir/private-seed"
  python3 -B scripts/update_tools.py release \
    --app "$work_dir/Countdown Manager.app" \
    --private-key "$signing_dir/private-seed" \
    --download-url-prefix 'https://github.com/VDevGushin/CountdownManager/releases/download/v1.16.0/' \
    --output "$work_dir/release"
)
```

The numbers above configure the local 1.16.0 / build 31 preparation procedure; its evidence
is tracked in [releases/v1.16.0.md](releases/v1.16.0.md). They do not establish publication.
For subsequent releases, change the version,
build number and archive tag together, using a `CFBundleVersion` greater than the latest distributed
build. Distributed 1.16.0 uses build 31; previous 1.15.0 uses build 30. Keep `local.countdownmanager.app`
and existing data locations unchanged.
The output directory must be empty. These commands stage a bundle and prepare local artifacts;
they do not install in `/Applications`, commit, upload, publish or modify production event data.

Weather in 1.9.0 uses Open-Meteo independently of Sparkle and remains off until enabled by the user.
Account-free weather does not require an Apple Developer membership or a weather API key.
First-install location permission, native AUTO location and VPN behaviour are separate acceptance
surfaces; a successful public forecast request for Moscow coordinates does not establish them.
Current published release status is recorded in [releases/v1.16.0.md](releases/v1.16.0.md);
previous release evidence is retained in [releases/v1.15.0.md](releases/v1.15.0.md).
The original weather implementation and acceptance history remain in
[releases/v1.9.0.md](releases/v1.9.0.md). Pirate Weather and 7Timer are excluded.
An earlier 1.10.0 candidate returned decoded batches from all three services and a consensus
for an isolated eligible event. That historical CLI result is not a live-service test of the
1.12.0 transport/controller and does not establish GUI HTTP, AUTO location, another Mac,
VPN or sustained availability.

The bundle contains the complete Sparkle framework, copied with symlinks and permissions preserved.
Nested XPC services, helper executable and Updater app are signed inside-out, preserving Downloader
entitlements, then the framework and host app are ad-hoc signed and verified. ZIP creation uses
`ditto --keepParent`; `generate_appcast` signs the feed and the archive. The release tool verifies
both signatures and checks enclosure version, URL, length and signature. Delta updates are disabled
for this initial release path. It writes `release-manifest.json` for provenance.

Publish the verified archive and signed appcast as a separate authorized operation. Do not edit
the appcast after signing; regenerate it if URLs/content change. Before distributing, verify public
anonymous HTTPS access and run an actual update against two independent release-like builds.

## Disposable local update test

```sh
python3 -B scripts/prepare_update_test.py --output /private/tmp/countdown-update-test-new
/private/tmp/countdown-update-test-new/serve-feed.sh
# In another terminal/session:
/private/tmp/countdown-update-test-new/launch-older.sh
```

The preparer makes separate older/newer bundles, increasing build numbers, a test-only Ed25519
seed file outside the repository, signed artifacts, and a manifest. It never accesses production
Keychain. Both bundles carry `local.countdownmanager.update-test` and a durable marked test home
so that Sparkle's relaunch stays isolated without env/argv inheritance. Only explicit test bundles
permit loopback HTTP. Keep test keys separate from production signing and delete the generated
temporary fixture directory when no longer needed.

Use ordinary update controls to exercise the full download, guarded install, replacement and
relaunch. Prepared artifacts alone do not prove an update succeeded. The acceptance matrix and
limitations are in [VERIFICATION.md](VERIFICATION.md).

Before interactive updater UI, the host hides its retained panel and temporarily uses an ordinary
window level. Explicit reopening preserves the editor and timer; later native updater windows can
take focus. Ending the update session restores the panel level without reopening it. A deferred
installation explains the blocker and offers `Вернуться к работе`; installation resumes only through
another explicit ready-update action after a fresh safety check.

Verification capabilities, the native acceptance matrix and platform limitations are maintained in
[VERIFICATION.md](VERIFICATION.md). Keep build provenance and per-run acceptance receipts with the
prepared artifacts. Local fixture acceptance does not establish public HTTPS availability, Gatekeeper
first installation, Intel support or runtime compatibility on older macOS. After publication, verify
that the signed feed and archive are anonymously accessible at their configured URLs.

Primary framework references: [Sparkle setup](https://sparkle-project.org/documentation/),
[customization](https://sparkle-project.org/documentation/customization/),
[updater delegates](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html),
[signing nested components](https://sparkle-project.org/documentation/sandboxing/).
