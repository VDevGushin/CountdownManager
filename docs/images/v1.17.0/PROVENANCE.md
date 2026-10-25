# Countdown Manager 1.17.0 / 32 — native release evidence

The production candidate executable is
`7b50b24d55c1e3abab64ae87af46170619551fd445a5bd1b4e114cb4dcc00a2d`.
The same signed bundle was used for both native runs and the audited release ZIP.
The icon turns only in the status bar; Dock retains its normal static application icon.

The focused menu route passed **3/3** in **22.221 seconds**, producing 24 images.
It observes the real status layer's quarter/half-turn presentation matrices, explicit cleanup
at the 12-second deadline, timer interruption without resumption and restart on another opening.
Dock content remains unchanged throughout. The native desktop route passed **27/27** in
**50.843 seconds** and produced 110 images. Both runs exited zero, kept the executable unchanged
and reported no main-thread stall. Their marked homes contain only demonstration events and
synthetic weather; production data is not used as a fixture.

All 24 menu images and five selected desktop/mini images are retained here. Full manifests and
native results identify the original sets: [menu manifest](menu-identity/manifest.json),
[menu run](menu-identity/run-receipt.json), [desktop manifest](desktop/manifest.json),
[desktop run](desktop/run-receipt.json). Other desktop images remain in the local release work
directory. Default/Dark `icon-source-*.png` are native Icon Composer source exports; these are
distinct from ICNS captures or a forced system Dock appearance.

Strict SwiftLint passed **0/73**. Final CoreChecks/UIChecks passed after repairing a test-only
unhosted CALayer fixture: committing that detached layer's transaction discarded its animations,
so deterministic fixture assertions remain synchronous; real timing is checked in the attached
native status layer. The earlier completion timeout was a separate failed attempt and led to
explicit cancellable deadline cleanup. Neither failed attempt is counted as PASS.
[Acceptance summary](acceptance.json), [build input hashes](source-inputs-at-build.json) and
[final verification hashes](source-inputs-final-verification.json) distinguish the two test-only
file revisions after the candidate build from unchanged application sources/resources.

The [public-key-only artifact audit](artifact-audit.json) verifies ZIP/feed signatures, rejects
tampered messages/signatures and matches all 166 extracted tree entries to the candidate.
The [fresh genuine update](genuine-update-final.json) records published 1.16.0/31 → 1.17.0/32
at the same isolated path: exactly one new process appeared automatically before any UI re-query
or manual reopening, with unchanged synthetic JSON/checklist/favorite and Dark preference.
The test used a disposable key and loopback HTTP. Its private key was deleted and host/server
were stopped afterward. [Settings after the update](genuine-update-after.png) shows 1.17.0.

Still images and numerical layer samples do not establish perceived compositor smoothness,
physical status-item clicks, real wallpaper contrast, older macOS, Intel, Gatekeeper first
installation, Spaces or full VoiceOver. Publication and anonymous-download evidence are recorded
separately once completed.
