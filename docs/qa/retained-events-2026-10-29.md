# Retained events — 2026-10-29

Status: historical pre-integration implementation evidence, verified within the limits below.
Branch: `codex/retained-events`. These checks used the earlier 1.18.1/build 34-labelled candidate.
The release integrates the published 1.19.0 material/link source line and targets **1.20.0/build 36**.
Final package and publication status are recorded in [release 1.20.0](../releases/v1.20.0.md);
the earlier hashes and PASS totals below are preserved rather than relabelled as final-package evidence.

## Accepted behaviour

The third native event option is `Сохранять после даты события`, below weather and primary.
It defaults to off for new/day/legacy events. Saved retention keeps the event, identity, date,
note, task completion, saved links and owned file copies after the civil date. Past labels are `Вчера` or
`N дней назад` in secondary ink. The primary stays above the list and in the menu; it is not
duplicated. Other past events are last, recent first, under `Прошедшие` on desktop and without
an extra section on mini. Equal dates retain input order.

Editing a retained past event may keep its exact saved date or move to today/future. Creation
backdated or moving to another past date is rejected. A draft flag cannot resurrect an ordinary
event that expired before Save. Unchecking past retention and Save opens the existing explicit
delete confirmation; Cancel preserves the event/draft. Successful deletion removes owned copies
only after durable event writing, leaving originals untouched. Failed writes retain retry context.

## Automated evidence

- Initial full SwiftLint: 0 violations in 77 files.
- CoreChecks passed: strict optional metadata; four civil boundaries including year/leap day;
  invalid/stale edits preserve snapshots; legacy notes and 17 attachments remain editable;
  real copied bytes survive restart/expiry; failed delete and retry preserve the storage contract.
- CoreChecks + UIChecks passed after correcting test access to existing package APIs. The new
  workflows cover stable desktop/mini ordering/search/primary, Russian labels, draft choices,
  failed midnight/edit writes and explicit retry. An earlier build failed due to tests calling
  internal Store APIs; test code was corrected without broadening production visibility.
- Final full SwiftLint: 0/77. Final CoreChecks + UIChecks passed.
- First native desktop run failed after 20 scenarios at the existing favorite-only-month assertion.
  On October 29 the hidden parent contains November (today + 3 days), while the monthly fixture
  has a November favorite and no ordinary November group. Their unscoped test registry collided.
  The monthly fixture and helper lookups now use their own scope, retaining the same absence
  assertion; production rendering was not changed to satisfy the test. The complete native rerun passed 29/29. One Dark feed still was caught during the mode transition;
  seven retention stills passed visual review. The capture scenario now waits for a full-width feed
  row and three stable document-height observations before theme capture. The settled full rerun passed **29/29** and independent visual review accepted **8/8** retention images.
  The misleading earlier frame is retained only in temporary raw diagnostics, not the README.
- Two targeted external XCUITests were built but neither test began: XCTest runner failed with
  `Timed out while enabling automation mode.` This is unavailable external-XCTest evidence, not PASS.
- Direct native UI fallback on a separate isolated debug build exercised the actual third checkbox:
  default OFF, click ON, conditional explanations, Save and persisted `keepsAfterDate=true` with
  unchanged primary; a fresh process loaded ON, and click OFF → Cancel preserved the saved flag.
  The test copy had a separate bundle identifier to distinguish it from the installed app. No
  external confirmed-delete or VoiceOver claim is made from this fallback. All temporary app
  processes launched for this fallback were closed afterward.

## Isolation and limits

All tests use temporary files, separate preferences and synthetic event/file data. No production
Countdown data is used as a mutable fixture. No installation, commit, push or publication was part
of this implementation-evidence stage. The subsequent release is tracked separately. Older versions that ignore retention may expire these events and delete their owned
copies; downgrade recovery requires matched JSON and Attachments backups.

Controlled-clock midnight tests establish civil-day policy, not physical sleep/wake timing.
Settled screenshots do not establish absence of transient flicker. Direct native UI fallback covers checkbox clicks, fresh-process loading and draft cancellation.
The confirmed-delete path is covered by in-process native and core tests; its new external XCUITest
remains unexecuted. VoiceOver speech, IME and external date-picker entry were not checked.

## Integrated 1.20.0/36 release acceptance

The feature was subsequently integrated with the published 1.19.0 links/materials/guide source
line. Its exact signed 1.20.0/36 package passed **60/60 unique native scenarios**: desktop 30,
mini 23, editor 5, materials 1 and release help 1. Current source gates passed SwiftLint 0/89,
CoreChecks/UIChecks, design-source 7/7, build-contract 18/18 and update-tool checks 12/12.

These results are separate from the pre-integration counts and hashes above. The exact final
executable, unchanged runtime hash, twelve fresh images, artifact signatures and compatibility
boundaries are recorded in [release status](../releases/v1.20.0.md),
[native receipt](../images/v1.20.0/native-production.json) and
[artifact audit](../images/v1.20.0/artifact-audit.json). The release was published as Latest on
2026-10-29; the [anonymous receipt](../images/v1.20.0/publication.json) confirms HTTP 200 and exact
audited ZIP/version-feed/stable-feed hashes. No local installation was performed.
A real 1.19.0 → 1.20.0 update/relaunch was not rerun, and the external XCTest limitation remains.

## Durable receipts and current images

- [Structured result](retained-events-2026-10-29/receipt.json)
- [Final CoreChecks and UIChecks output](retained-events-2026-10-29/fast.log)
- [Final full SwiftLint output](retained-events-2026-10-29/lint.log)
- [Native 29-scenario result](../images/v1.18.1/retained-events-candidate/ui-smoke-result.txt)
- [Current native image provenance and hashes](../images/v1.18.1/retained-events-candidate/PROVENANCE.md)

The implementation-stage images below remain historical. README release images are refreshed
separately for 1.20.0/36, preserving these earlier hashes and historical published release images. The complete raw capture sets/tested bundles are preserved temporarily
under `/private/tmp/countdown-retention-full-evidence/`.
