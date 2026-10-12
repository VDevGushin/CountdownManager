# Signed Sparkle updates without Apple credentials

Status: ACCEPTED
Date: 2026-10-11

## Decision

Use pinned Sparkle 2.10.0, ad-hoc signed app-bundle ZIPs and a persistent Ed25519 release key.
Require signatures on both the appcast and archive, verify archives before extraction, and
disable expired signed-feed fallback. Serve production feeds and downloads over public HTTPS.
The updater starts only in explicitly configured distributions. Build tooling never creates a
production key, accesses Keychain, installs into `/Applications` or publishes artifacts.

Use Sparkle's standard UI and its own scheduling, download, validation, installation and relaunch.
Automatic checks can be disabled independently from manual checks. Silent installation is disabled.
Use the native postponed-relaunch continuation and the application's final termination boundary
to protect any open editor, pending event persistence and a running timer. Resume deferred
installation only after an explicit action and another state check. Preserve ordinary user Quit.

The editor presentation has one shared session owner; update safety observes that owner without
replicating the draft or changing Save/Cancel semantics. Event and timer persistence remain in
their existing owners and formats.

Coordinate standard updater UI through public user-driver delegate callbacks. Hide the retained
status panel before presentation and temporarily use its ordinary window level while the update
session exists. This avoids the anchored panel's `.popUpMenu` level covering Sparkle's normal windows,
while explicit reopening still lets the user finish an editor or timer. Restore only the level after
Sparkle's finish callback unwinds; never reopen implicitly or inspect Sparkle's private windows.

## Rationale and limits

Ad-hoc app signing plus Ed25519 archive authentication provides a no-paid-account update path.
It does not establish Apple Gatekeeper trust for the first installation. With no Developer ID
fallback, loss of the release key needs a manually installed recovery version.

Native postponement is called before final installation, but is not universal and its continuation
is consumed only once. `willInstallUpdate` precedes the native termination request, so the AppKit
termination guard catches activity appearing after download or continuation. Sparkle's installer
waits for host termination before replacing the application and provides a native retry.

Real update fixtures use a separate bundle ID and a validated isolation root inside both plists.
Sparkle's relaunch does not preserve original environment/arguments; inheriting them cannot be
the data-protection mechanism. Loopback HTTP is confined to those explicit fixtures.

## Evidence and revisit

[Pinned installer driver](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUInstallerDriver.m),
[native updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html),
[host termination/replacement](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Autoupdate/AppInstaller.m),
[Sparkle setup/security](https://sparkle-project.org/documentation/).

Verification capabilities and remaining external acceptance belong in `docs/VERIFICATION.md`.
Release steps belong in `docs/UPDATES.md`. Revisit postponement and signing constraints if silent
installation, Developer ID signing, key rotation, sandboxing or another distribution architecture
is adopted.
