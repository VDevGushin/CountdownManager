# Signed releases and updates

## Current release

Published as Latest: **1.20.3 / build 39**, timer alarm clipping correction.
Anonymous ZIP, versioned appcast and stable appcast passed HTTP 200 and exact hash checks.
The previous release is **1.20.2 / build 38**. [Publication receipt](images/v1.20.3/publication.json).
[Release status](releases/v1.20.3.md) · [Notes](releases/v1.20.3-notes.md) ·
[Package audit](images/v1.20.3/artifact-audit.json).

This document describes the current release procedure. Per-version reports under `releases/`
and evidence linked by them are records of those runs, not alternate current instructions.
The project release skill is [countdown-release](../.agents/skills/countdown-release/SKILL.md).

## Stable identity

- Bundle: `local.countdownmanager.app`.
- Stable feed: `https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml`.
- Archives: `https://github.com/VDevGushin/CountdownManager/releases/download/v<VERSION>/CountdownManager-<VERSION>-<BUILD>.zip`.
- Existing production Keychain account: `local.countdownmanager.app.sparkle.production`;
  service: `https://sparkle-project.org`.
- Public-key fingerprint, SHA-256 of the decoded 32 bytes:
  `327e6e5300e230c81fc087b79bb529dae667723cefd319a4c706fb57562a80b2`.

Use this named account. Sparkle's default `ed25519` account is not the project's production key.
`generate_keys --account <account> -p` reads only its existing public key; do not generate a
replacement key or print/export the private key as part of routine release preparation.
The current Sparkle tools can sign directly from the named Keychain account.

The default `build.sh` disables the updater. A release must explicitly configure the unchanged
stable HTTPS feed and public key. The app requires signed feeds and archive verification before
extraction, with signature-failure fallback disabled. No token, private seed or test preference
profile belongs in the bundle or release assets.

## Prepare one candidate

Begin release preparation only on the owner's separate release instruction. Feature completion,
merge and a push to `main` do not imply a version bump, release tag or publication. Product work
uses feature branches; independent skills/harness/documentation maintenance uses `main`, as defined
in [the Git workflow](../AGENTS.md#git-workflow).

Check the actual GitHub default branch, release branch, remote heads and last published tag.
A newer release branch does not update the README seen on GitHub's default `main` branch.
Resolve the branch relationship under the authorizations in [AGENTS](../AGENTS.md); do not call
an unmerged branch's documentation the current repository homepage.

Read version/build from `Resources/Info.plist`. Update `WhatsNewView.releaseID`, its user-facing
text, Markdown/HTML notes, README and current PRODUCT/ARCHITECTURE/DESIGN/UPDATES references.
Current README screenshots must come from the candidate on isolated data, with provenance;
remove obsolete galleries from the homepage instead of appending another release chronicle.
Check local links and image references across maintained documentation.

Use [VERIFICATION](VERIFICATION.md) for the changed failure mode. A timer-state test does not
prove an emoji is whole; inspect the rendered result at native scale. Identify the running app
by path, version and executable hash before attributing a screenshot to the candidate.

After a local build has resolved the pinned Sparkle package, preparation can follow this example:

```sh
set -euo pipefail
key_account='local.countdownmanager.app.sparkle.production'
build_dir="$PWD/.build"
sparkle_tools="$build_dir/artifacts/sparkle/Sparkle/bin"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
public_key=$("$sparkle_tools/generate_keys" --account "$key_account" -p)
release_work=$(mktemp -d /private/tmp/countdown-release.XXXXXX)

COUNTDOWN_UPDATE_MODE=release \
COUNTDOWN_UPDATE_FEED_URL='https://github.com/VDevGushin/CountdownManager/releases/latest/download/appcast.xml' \
COUNTDOWN_UPDATE_PUBLIC_KEY="$public_key" \
BUILD_DIR="$build_dir" APP_OUTPUT_PATH="$release_work/Countdown Manager.app" ./build.sh

mkdir "$release_work/assets"
archive_stem="CountdownManager-$version-$build_number"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$release_work/Countdown Manager.app" "$release_work/assets/$archive_stem.zip"
cp "docs/releases/v$version-notes.html" "$release_work/assets/$archive_stem.html"
"$sparkle_tools/generate_appcast" --account "$key_account" \
  --download-url-prefix "https://github.com/VDevGushin/CountdownManager/releases/download/v$version/" \
  --maximum-deltas 0 --embed-release-notes "$release_work/assets"
```

The actual resolved artifact folder can differ in case; locate the single pinned Sparkle
`bin` directory rather than creating another dependency checkout. Respect the native build
contract and record actual SDK/link compatibility. A rebuilt or re-signed executable gets a
new hash: do not relabel earlier screenshots or runtime results as exact-package evidence.
Reuse checks whose subject is unchanged, and rerun the affected surface after a real change.

Verify the final ZIP and feed with the public key embedded in the app, including rejection of
mutated payloads. Validate archive URL/length, version/build, minimum OS, hardware requirement,
embedded notes and exact signed-feed byte boundary. Extract the ZIP and compare file bytes,
modes and symlinks; run strict/deep codesign. Record the archive and feed hashes.
Ad-hoc app signing is not Apple notarization or universal Gatekeeper acceptance.

## Publish through the in-app browser

The established user workflow is GitHub's release page in the **in-app browser**. Open the
existing authenticated session and publish there. Do not replace it with CLI/API authentication
or credential discovery merely because another tool exists. If this path is unavailable, explain
the actual limitation and agree on a fallback before changing the publication method.

If a reviewed feature is part of the requested release and not yet integrated, merge it into
`main` under the existing authorizations. Use clean, up-to-date `main` for the final release source,
build and verification, then create the annotated version tag on that reviewed main commit.
Do not move an already published tag. After the feature, release and follow-up documentation
are complete, leave the working checkout on up-to-date `main`, preserving unrelated changes.

Use that reviewed main commit and version tag. Upload only the audited ZIP and
signed `appcast.xml`; release notes are embedded. Confirm exact filenames, completed uploads,
title/notes and the Latest setting before publishing. Keep permission boundaries in AGENTS;
this procedure does not grant commit, push, main integration, publication or installation rights.

After publication, check anonymously:

1. `/releases/latest` resolves to the intended version.
2. The versioned ZIP and versioned appcast return HTTP 200 and exact local hashes.
3. The stable appcast returns the same signed feed and names the intended archive/build.
4. The tag points to the reviewed source, and the default-branch README displays the current
   version, graphite design and working image/download links.

Only then change status from candidate to published and save a publication receipt. Keep
source commits and the immutable tag distinct from a later documentation receipt commit.
A browser's “Publish” action or an authenticated download alone is not this verification.

## Finish on the owner's previous release

The owner's requested finish is to test the update personally. After successful publication,
leave the **previous published release** installed and running, rather than installing the new
release for them. Determine “previous” from the release actually being superseded, not a fixed
version. If the installed app already matches that published package, verify and retain it.
Otherwise verify the previous public ZIP/signature, preserve current user data/preferences and
use a reversible replacement. Never reset or downgrade the data schema as part of this step.

Close only identified isolated candidate/test instances. Enumerate task-created bundles,
profiles, build caches and temporary tooling. Clean them only after retaining the required
release receipts and checking running process paths. Prefer recoverable Trash moves with a
manifest. Preserve production data, keys, Git history, project skills and the published artifacts.
Do not treat pre-existing unrelated temporary directories as this task's cleanup scope.

## Genuine update acceptance

`python3 -B scripts/prepare_update_test.py --output /private/tmp/<fresh-directory>` prepares
separate marked bundles and a loopback feed with a disposable test key. It neither uses the
production Keychain key nor authorizes a production data fixture. Follow its emitted instructions
and the acceptance matrix in [VERIFICATION](VERIFICATION.md).

Preparation alone is not a successful download/install/relaunch. Match the evidence to the
mechanism changed; do not claim a real public-version update from an in-process guard test.
The owner's final manual update is separate from any synthetic mechanism test.

Primary framework references: [Sparkle](https://sparkle-project.org/documentation/),
[customization](https://sparkle-project.org/documentation/customization/),
[updater delegates](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html).
