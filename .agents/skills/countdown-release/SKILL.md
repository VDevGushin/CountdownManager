---
name: countdown-release
description: Prepare, publish, verify and finish a Countdown Manager release, including current documentation, native screenshots, GitHub homepage, signed Sparkle assets, cleanup and the previous installed version for the owner's manual update. Use for this project's releases and release readiness reviews, not ordinary feature work or other projects.
---

# Countdown Manager release

A release is complete when the public package, update channel, default-branch homepage and local
handoff state agree. A successful build or Publish click proves only that step.

Read [AGENTS](../../../AGENTS.md) for authority, [UPDATES](../../../docs/UPDATES.md) for the
maintained channel/signing/publication procedure, and [VERIFICATION](../../../docs/VERIFICATION.md)
for sufficient evidence. Native implementation/design/QA use their existing project skills.
Do not copy their full instructions here or invent a new release process each time.

## Establish the release

- Inspect actual worktree/branch/remote heads, GitHub default branch, last published version/tag,
  installed application path/version/hash and current candidate. Do not infer one from another.
- Read version/build from `Resources/Info.plist`. Identify the change, reviewed source commit,
  previous published package and final candidate. Record permissions already granted in the chat;
  ask only for a still-missing consequential action under AGENTS, after making it reviewable.
- Preserve the user's work and production events/preferences. Fixtures always use marked isolated
  profiles and LaunchServices. Do not change unrelated features to make a release test pass.

## Reconcile current documentation

Review README, PRODUCT, DESIGN, ARCHITECTURE, VERIFICATION, UPDATES, release notes and native
`WhatsNewView.releaseID`/copy against actual code and accepted behaviour. Search the maintained
surfaces for stale version claims, placeholders, broken links and obsolete screenshots.
Update only contracts actually changed. A blanket version replacement corrupts historical evidence.

The homepage should describe the current product, with a current download link and a small set of
fresh candidate screenshots. Remove old release chronicles and galleries from README; the owner
has rejected accumulating a separate archive there. Existing version-specific evidence is not a
current UI gallery. Follow AGENTS for preserving release evidence; a cleanup request does not
silently authorize deleting unrelated history or production data.

Use the real app, isolated demonstration data and the ordinary build/SDK/style route. Open and
inspect every image used on the homepage at its intended size. For a visual bug, inspect the
reported region, not just the surrounding screen or passing state assertions. Before saying a
user screenshot is fixed or stale, verify which running app produced it. If useful, launch the
candidate for the owner to inspect without replacing their installed app.

Run `python3 .agents/skills/countdown-release/scripts/check_release.py --root .` for mechanical
version, homepage-image and local-reference checks. This does not establish visual/product truth.

## Verify and freeze one package

Select checks for the actual change from VERIFICATION; do not rerun unrelated suites by habit.
Run UI drivers that need native focus sequentially. If one fails, retain its result and identify
the failed step before changing production code. A targeted repeat is not a clean full run.

Freeze the candidate before capturing exact-package evidence. Changing source during compilation
invalidates that build. Rebuilding, reconfiguring or signing can change the executable hash;
match the final bundle to its receipts and rerun only evidence invalidated by the change.
Retain the useful screenshots/manifests and results, not every temporary duplicate.

Use the existing production identity, feed and **named** Keychain signing account from UPDATES,
not Sparkle's default account. Never discover GitHub credentials by probing Keychain services.
Verify ZIP/feed using the app's public key, altered-input rejection, exact feed signature boundary,
metadata/notes, extraction bytes/modes/symlinks and strict/deep codesign. Do not edit a signed feed.
Distinguish ad-hoc app signing, Sparkle authenticity and Apple notarization.

## Publish using the established browser workflow

The owner uses GitHub's release page in the **in-app browser**. Reuse that authenticated session;
do not substitute CLI/API authentication or a different browser just because it is available.
If this route is unavailable, explain the actual limitation and agree on a fallback. Do not ask
for another approval for an already authorized action merely because the tool changed.

Under the authorizations in AGENTS, commit/tag/push the reviewed source and integrate it into the
actual default branch. A release branch or tag alone does not update the GitHub homepage.
Check branch ancestry/conflicts and preserve existing history and repository protections.

Select the pushed existing tag in the release form, use the reviewed notes, upload only the
verified production ZIP and signed appcast, wait for both uploads, then publish as Latest.
If the form was opened before the tag was pushed, refresh its tag data and recheck retained fields.
Do not create another tag to work around a stale selector. Save visible publication proof.

## Verify publicly, then finish

Check anonymously that Latest resolves to the intended tag, the ZIP/versioned appcast/stable
appcast return HTTP 200 with audited hashes, and the tag targets the reviewed source. Verify the
actual default-branch README and its displayed images/download links. Only then mark published,
write the receipt and push publication documentation. The optional checker `--public` verifies
these public bytes and default README equality; browser inspection still establishes appearance.

After successful publication, the owner's normal handoff is:

1. Leave the **previous published release** installed and running so the owner can update it
   personally. If already exact, verify and retain it; otherwise use the verified previous public
   package and a reversible replacement with user data/preferences preserved. Do not install the
   new release, silently downgrade newer user data, or trigger the owner's update yourself.
2. Close only identified candidate/test processes. Enumerate task-created temporary bundles,
   profiles, caches, downloaded tooling and seed exports; check running paths and retain necessary
   receipts before cleanup. Prefer Trash plus a restore manifest. Do not sweep pre-existing files,
   keys, production data or Git history into “trash.”
3. Report the published link/version, public verification, documentation/main status, installed
   previous version, cleanup result and material untested boundaries. Keep the report short.

A skill supplies instructions, not permission. A future user can override this normal handoff;
resolve a real conflict from the current chat rather than treating a prior preference as an
irrevocable product requirement.
