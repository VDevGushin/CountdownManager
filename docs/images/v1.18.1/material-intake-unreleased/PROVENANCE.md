# Material intake — implementation and bounded acceptance

Historical record: the user subsequently rejected addition Undo and its entire status row.
They have been removed; current evidence is in ../native-design-system-2026-10-28/PROVENANCE.md.
The earlier passes certify the earlier implementation only and do not establish its approval.

Date: 2026-10-28 (Europe/Moscow). Branch: `codex/event-links`, based on `14dc489`.
Uncommitted, unpublished development over version 1.18.1 / build 34.

## Implemented

Files and HTTP/HTTPS links can be dropped on desktop cards/details and mini cards. Saved-event
additions commit through Store and offer identity-only Undo. Editor drops belong to its retained
draft. Clipboard/plain text opens an editable filename/content composer and creates an ordinary
owned UTF-8 attachment. Clipboard is read only on an explicit action. Existing attachment/link
limits, copy ownership, previews, disclosure families and native symbols are preserved.

The accepted-provider reservation begins before asynchronous decoding. Cancellation releases only
its own token; late delivery cannot clear a newer operation. Saved additions reserve synchronously
before scheduling persistence, revalidate the current owner after copying and merge with the latest
event. Nested text composition retains the original editor and attachment draft owner.

## Automated evidence

- Strict SwiftLint: zero violations across 84 Swift files; `lint.txt` (quiet successful run).
- CoreChecks PASS: `final-core-checks.txt`.
- UIChecks PASS: `final-ui-checks.txt`. New checks cover preferred provider representation, a
  deliberately delayed/cancelled/replaced provider, synchronous admission, target identity, original
  and owned bytes, Unicode/1000-line UTF-8 content, filename validation, Cancel, both caps, partial
  import failure, failed persistence cleanup, stale owners and expiry. Existing suites also pass.
- Final native desktop campaign: **28/28** in `desktop-final.txt`, launched through LaunchServices
  in `/private/tmp/countdown-materials-desktop-qa-final`, with its mandatory isolation marker.
  The final campaign log contains no `ui.stall` entry. It covers existing sheet/window/editor,
  divider, shared mini/desktop state, links/disclosures, attachments, CRUD and weather/layout gates.

Historical failed runs remain in `desktop-first-failure.txt`, `desktop-second-failure.txt` and
`desktop-third-failure.txt`. Each stopped after seven scenarios at an overly specific hit-test
oracle requiring nil under a sheet. Native drop/context-menu registration may retain the inert root
NSHostingView. The revised oracle accepts only nil or that exact root, rejects interactive child/
divider hits, and adds checks that background actions are disabled. Product sheet exclusion remains.
Do not combine those failed attempts with the final 28/28 or describe them as additional passes.

## Native interaction observed with CUA

All event/file mutations used freshly created `.build/materials-preview/TestData`, never production
data or the earlier links tester's user-edited data.

- Desktop editor: create a named multiline text attachment, Cancel the entire event, confirm
  persisted JSON still has no attachments and its draft-only owned directory is gone.
- Repeat creation and Save: the owned file has exactly the expected UTF-8 bytes, paragraphs and
  trailing newline. The resulting saved summary shows one attachment.
- Desktop Paste with no active field: opens the composer with the supplied synthetic clipboard
  fragment and a first-line filename. Create yields two attachments and Undo returns to one.
- Paste in the search field changes the query and selects the matching event; it does not open
  attachment composition or create data.
- Mini: original timer and 390×600 panel remain, attachment section starts collapsed with count one.
  Editor opens the composer internally. A colon-containing filename shows its reason and disables
  Create; a valid filename enables it. Composer Cancel returns to the retained editor; event Cancel
  returns to the unchanged saved card.

CUA sometimes reported AX failure/noWindowsAvailable while a native sheet changed; reacquiring the
current app then showed the completed action. These driver errors are not counted as product passes
or product failures. Actual resulting UI and owned file bytes were inspected separately.

## Screenshots and build

`desktop-text-added.png`, `mini-text-collapsed.png`, and `mini-text-composer.png` are real dark native
captures from an intermediate tester with this interface. They precede the final hidden-editor
Save/Cancel guards and removal of an unused import parameter; do not label them exact-final-binary
captures. The designer inspected their native symbols, summary order, geometry and clipping in one
bounded batch. They do not certify Light/Increase Contrast, external gestures or compositor motion.

An attempted capture during the earlier locked session is preserved as
`capture-incomplete-locked.png` for diagnosis, not as an accepted screenshot. After the user unlocked
the Mac, `editor-text-composer-final.png` was captured from the correctly bound native sheet of the
final tester. README now references that final capture. No HTML rendering is presented as native UI.

The ordinary native SwiftPM build uses the macOS 15.4 SDK, deployment target 13.0, rather than the
SDK-27 Debug appearance. The QA and preview bundles contain the same compiled application with
different bundle identifiers/signatures. `evidence.json` records their hashes and final source inputs.

## Tester delivery and remaining manual acceptance

Tester: `.build/materials-preview/Countdown Materials Preview.app`.
Archive: `.build/Countdown-Materials-Preview.zip` (ZIP integrity checked).
The outer launcher calls `/usr/bin/open` on its nested native bundle, supplies the adjacent marked
TestData home and `--visual-preview --desktop-preview`. Both signatures are verified. JSON and owned
bytes were backed up before replacing its executable. Keep TestData beside the outer app.

**Not yet certified by external input:** actual Finder/browser drags, wrong-card hover/drop, status
icon mouse tracking, hover → Escape/outside-drop dismissal, return to a hidden mini editor during
drag, and all third-party item representations. Provider/model tests are not proof of these gestures.
Mail/Photos file promises, macOS 13 runtime and VoiceOver are not certified.

After unlock, CUA cross-window drag failed before beginning its gesture with
`windowNotFoundAtPosition((295.0, 130.5))`, even after left/right tiling and explicit activation through
LaunchServices. A fallback XCUITest campaign built successfully but its runner timed out while
enabling system automation mode, before either selected case executed. These are driver/setup
failures, not successful product scenarios or evidence of an application drop failure.
`CUA-drag-driver-failure.txt` and `external-driver-init-failure.txt` retain the details. The two new
focused methods (`testFinderFileDropTargetsUnselectedEventAndUndo` and
`testSafariLinkDropCreatesOnlyWebLink`) compile in a fresh `build-for-testing` run;
`external-test-build.txt` records that result. Runtime acceptance for them is still pending.

The user has been asked to perform the concrete Finder-file, Safari-link and status-hover actions;
application JSON and owned bytes will be inspected separately from that reported gesture evidence.
No publication, production installation, migration, commit, push or merge was performed.
