# 1.20.5 / build 41 native candidate evidence

Status: locally verified candidate; commit/main integration/push/tag were explicitly approved by
the owner after the initial automatic approval-review rejection. This package is not published and was built from the
uncommitted feature checkout, based on main `64be6a8320a6aa4d4ef39eabf40a062c7440659e`.
[Exact application input hashes](candidate-inputs.json) identify the actual frozen source; the base
commit alone does not contain this fix. The final release must follow clean-main source/tag rules.

## Package and native evidence

The [public-key audit](artifact-audit.json) verifies ZIP/feed Ed25519 signatures, changed payload
and signature rejection, exact signed-feed framing, embedded notes/metadata, extraction bytes/modes/
symlinks, strict/deep codesign and SDK compatibility. Named production Sparkle signing account,
bundle identity and stable feed are unchanged. Ad-hoc app signature; no Apple notarization claimed.

Executable SHA-256: `e68b32216c33b071402b7d762730e9c2916bc6d8caf59a2cac5059eeb1b112f4`.
Headers SDK 15.4, linked compatibility 13.0, Apple Silicon, minimum macOS 13.0.

The exact signed executable passed [compact 7/7](compact-result.txt), [desktop 31/31](desktop-result.txt)
and [release help 1/1](whatsnew-result.txt). Counts overlap and are not unique-test totals.
The compact runtime records 28 PNGs, including whole over-limit local-pasteboard insertion,
151/150, disabled Save, shortening/re-enabled Save, Unicode replacement, native Undo, provisional
and committed over-limit IME, title/subtask focus, native scrolling, legacy 151/280 and durable Save.

Manifests: [compact](compact-manifest.json), [desktop](desktop-manifest.json),
[release help](whatsnew-manifest.json). Retained homepage PNGs show the actual native candidate on
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
Task-created candidate artifacts are retained through final main packaging and publication.
