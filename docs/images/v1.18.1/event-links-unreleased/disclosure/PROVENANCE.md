# Links disclosure and desktop summaries — 2026-10-27

[Final completion: native 28/28 and external 3/3](../completion/PROVENANCE.md). This earlier evidence is retained unchanged.

Unreleased source on `codex/event-links`, still reporting 1.18.1 / build 34. These captures replace
the current README illustrations for the development feature; historical release images and the
earlier feature evidence in the parent directory are preserved.

## Build and images

The executable was built using the ordinary `build.sh` route, with updates disabled and
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`. Its build-version SDK field is
13.0. This is the existing native-control appearance, not Xcode's new-SDK Debug styling.
The [native manifest](native-manifest.json) and [receipt](evidence.json) record executable,
source and PNG hashes. All captures use separate demonstration events/preferences/files.

Ten native PNGs show Light/Dark:

- desktop collection and feed, favorite link count, ten-link/checklist/two-file coexistence,
  and a zero-link event with no indicator;
- mini links collapsed and expanded, with unchanged heading/count horizontal position;
- editor inline invalid-address error with Save disabled.

The feed capture waits for real rows to finish reflow without overlap before taking the image.
An earlier transition frame was rejected during visual review rather than presented as settled UI.

## Evidence

- Focused native sequence: **1/1**. It checks favorite/grid/feed counts and zero absence, real
  summary-host containment, collapsed default, repeated disclosure, hidden-row removal, ordinary
  hide/show retention, fixed heading/count alignment and unchanged JSON across disclosure/Cancel.
- External disclosure scenario: **1/1**, 24.596 seconds, ordinary header and trailing-count clicks
  with 0/1/10 links; hidden rows and exact JSON preservation. The first run's test body completed
  but teardown attempted a screenshot after premature app termination; this was fixed in the test,
  and the corrected run passed. Earlier results are not merged into a fictional all-green suite.
- The original external Save/Cancel/reopen tests in the parent evidence remain separate evidence
  for those unchanged editor paths. The disclosure test does not certify browser contents.
- Strict lint and CoreChecks/UIChecks are recorded in the receipt/adjacent accepted logs. These are
  distinct from actual native mouse delivery.

## Harness audit

See [native style harness audit](../../../../qa/native-style-harness-2026-10-27.md).
AGENTS, the three native skills and the style document now require per-surface sibling and icon
comparisons. The eval suite adds a concrete style-boundary case. Its infrastructure passed 33
checks; hook regressions passed 12; three skills passed structural validation. The new live agent
case has not been run and is not claimed as behavioral certification.

The earlier general desktop regression failure remains recorded in the parent evidence. This
focused pass does not certify that full suite, every macOS version, VoiceOver or every input method.

## Tester build

The separate `.build/links-preview` application was updated in place with the tested executable,
then re-signed and relaunched through its isolated launcher. Before relaunch, all ten non-log files
in its current TestData were compared byte-for-byte and retained, including the user's test
attachments. A complete backup was made. Later user edits naturally change the live JSON/files;
those are not restored over the user's work. No production store or installed application was changed.
