# Preparing signed updates

Version **1.10.1 / build 19** is published as GitHub's latest release and installed
in `/Applications`. It adds automatic privacy-limited weather diagnostics. The ad-hoc
bundle signature and Ed25519 ZIP/appcast signatures passed; anonymous ZIP and both
version-specific/latest appcast downloads match the locally signed hashes. The installed
and running executable matches the published archive. Production event JSON stayed
byte-identical; weather/keep-awake/timer preferences were preserved.

The source integrates pinned Sparkle 2.10.0 for macOS 13+ and the Apple Silicon build.
The exact executable retains its accepted ten screenshots and native PASS 5/5 evidence.
Temporary signing-key export was removed. Nineteen generated build/cache/duplicate
folders were removed after installation, retaining release archives and QA evidence.
Current status and limitations are in [releases/v1.10.1.md](releases/v1.10.1.md);
previous publication/installation history is in [releases/v1.10.0.md](releases/v1.10.0.md).
Release preparation, publication, public verification and installation remain separate operations.
Existing versions without Sparkle require one manual installation of an updater-enabled release.

## Channel and signing key

The selected stable feed is
`https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml`.
The published version-specific archive URL is
`https://github.com/VDevGushin/CountdownManager/releases/download/v1.10.1/CountdownManager-1.10.1-19.zip`.
The archive and signed `appcast.xml` are assets of release v1.10.1, selected as GitHub's latest.
Anonymous HTTPS downloads of the archive, version-specific feed and latest feed matched their
locally verified SHA-256 hashes; feed build 19, version 1.10.1, URL and length passed.
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
  COUNTDOWN_VERSION=1.10.1 COUNTDOWN_BUILD_NUMBER=19 \
  APP_OUTPUT_PATH="$work_dir/Countdown Manager.app" ./build.sh

  signing_dir=$(mktemp -d /private/tmp/countdown-release-signing.XXXXXX)
  trap 'rm -f -- "$signing_dir/private-seed"; rmdir -- "$signing_dir"' EXIT
  "$sparkle_tools/generate_keys" --account "$key_account" -x "$signing_dir/private-seed"
  chmod 600 "$signing_dir/private-seed"
  python3 -B scripts/update_tools.py release \
    --app "$work_dir/Countdown Manager.app" \
    --private-key "$signing_dir/private-seed" \
    --download-url-prefix 'https://github.com/VDevGushin/CountdownManager/releases/download/v1.10.1/' \
    --output "$work_dir/release"
)
```

The numbers above target local preparation of 1.10.1 artifacts, after acceptance;
they are instructions, not evidence that those artifacts have been prepared. For subsequent releases, change the version,
build number and archive tag together, using a `CFBundleVersion` greater than the latest distributed
build. The current distributed 1.10.1 uses build 19; choose a greater build for the next release. Keep `local.countdownmanager.app`
and existing data locations unchanged.
The output directory must be empty. These commands stage a bundle and prepare local artifacts;
they do not install in `/Applications`, commit, upload, publish or modify production event data.

Weather in 1.9.0 uses Open-Meteo independently of Sparkle and remains off until enabled by the user.
Account-free weather does not require an Apple Developer membership or a weather API key.
First-install location permission, native AUTO location and VPN behaviour are separate acceptance
surfaces; a successful public forecast request for Moscow coordinates does not establish them.
Current release status is recorded in [releases/v1.10.1.md](releases/v1.10.1.md).
The published weather implementation and acceptance history remain in
[releases/v1.9.0.md](releases/v1.9.0.md). Pirate Weather and 7Timer are excluded.
The current common transport/controller returned decoded batches from all three services
and a consensus for an isolated eligible event; this CLI-host evidence does not establish
GUI HTTP, AUTO location, another Mac, VPN or sustained availability.

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
