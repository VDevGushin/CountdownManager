# 1.20.5 / build 41 release evidence

Status: final clean-main package published as Latest and anonymously verified. The owner explicitly approved
commit, main integration, push and the annotated version tag. Application source was frozen on
clean main `5cee33bbcf0b37c0044db69b5072d7a05bfa44d0` before the final build. Later evidence-only commits do not change
these application inputs.

The initial feature-checkout candidate and its [input hashes](candidate-inputs.json) remain historical
evidence in the feature commit. The [comparison](main-candidate-comparison.json) detected a changed
executable after the final main build, so native notes, desktop, release-help scenarios and captures
were all repeated on the exact final package rather than relabelled.

## Package and native evidence

The [public-key audit](artifact-audit.json) verifies ZIP/feed Ed25519 signatures, changed payload
and signature rejection, exact signed-feed framing, embedded notes/metadata, extraction bytes/modes/
symlinks, strict/deep codesign and SDK compatibility. Named production Sparkle signing account,
bundle identity and stable feed are unchanged. Ad-hoc app signature; no Apple notarization claimed.

Executable SHA-256: `5fd3d0a683c5687147e05044c1c192030f2ff0a14958e4569ea68ac941274db7`.
Headers SDK 15.4, linked compatibility 13.0, Apple Silicon, minimum macOS 13.0.

The exact signed executable passed [compact 7/7](compact-result.txt), [desktop 31/31](desktop-result.txt)
and [release help 1/1](whatsnew-result.txt). Counts overlap and are not unique-test totals.
The compact runtime records 28 PNGs, including whole over-limit local-pasteboard insertion,
151/150, disabled Save, shortening/re-enabled Save, Unicode replacement, native Undo, provisional
and committed over-limit IME, title/subtask focus, native scrolling, legacy 151/280 and durable Save.

Manifests: [compact](compact-manifest.json), [desktop](desktop-manifest.json),
[release help](whatsnew-manifest.json). Retained homepage PNGs show the actual final native package on
isolated demonstration data: desktop feed Dark, desktop collection Light and note overflow Dark.
The matching Light overflow image is retained too. All four were opened and visually inspected.
The counter is red in both themes; the complete pasted text remains and Save is visibly disabled.
Synthetic weather is a layout fixture, not a live forecast.

[Strict SwiftLint](lint.log), [native design checks](design-checks.log), [CoreChecks](core-checks.log)
and [UIChecks](ui-checks.log) passed on the final source. Final core/UI commands used the same
native SwiftPM targets as `verify.sh fast`, reusing `.build` after packaging. A previous unchanged-domain
fast run also passed. A concurrent intermediate repeat was invalidated by a subsequent test-source edit;
it is not counted as a pass. The final application input manifest was rechecked byte-for-byte.

## Earlier attempts and limits

The first native attempt read Save enabled state before SwiftUI registration settled; it failed
before scenario 1. The driver now waits for the observable enabled state. The next attempt passed
all 7 behavioural scenarios, then failed the old 26-image manifest expectation after adding two
new overflow captures. The expected set is now 28. The final exact-package run passed independently;
the earlier failures are not combined with it into a clean first attempt.

External XCUITest expectations were updated for visible overflow/Save/Undo; that external suite was
not rerun. In-process NSTextView/local-pasteboard evidence does not certify external Command-V routing,
physical IME input, VoiceOver announcements or every input source. No updater mechanism changed;
a real download/install/relaunch was not rerun. General attachment/Spaces campaigns were not repeated.

[Local handoff](local-handoff.json): the installed/running previous 1.20.4/40 matches the anonymously
retrieved public archive in bytes/modes/symlinks and passes strict/deep codesign. It was retained for
the owner's manual update. Native candidate processes exited; production data was never a fixture.
[Cleanup](cleanup.json): 13 task-created entries (826,728 KiB) were moved recoverably to Trash with a restore manifest. Final ZIP/feed and receipts remain in `.build/releases/1.20.5/`; unrelated historical releases and production data were preserved.

[Public receipt](publication.json) confirms Latest, ZIP, versioned/stable appcast HTTP 200 and exact
package hashes. The annotated tag targets `f4d894d5df2005c14aa606c25591cac730a4b548`; default main
receives the final publication documentation separately. [Browser proof](publication-browser.png).

## Final homepage verification

The post-publication [raw-response check](raw-readme-stale-check.json) passed all asset hashes but
failed README equality because raw main still returned the earlier candidate text. The [three raw
responses](homepage-public.json) preserve this discrepancy; a request for the exact publication
commit already matched the current local README. The final [main Contents API/blob check](homepage-current.json)
returned the published README with the exact local Git blob and SHA-256. The real GitHub main page
also displayed published 1.20.5, the correct ZIP link and all three loaded native images. This
resolves current default-branch content independently of that stale raw response; the failed
checker is retained as a failure, not relabelled as a pass.
