# Desktop-only refinements — focused acceptance

2026-10-23, Europe/Moscow. Branch `codex/desktop-window`; not committed, released or installed
in `/Applications`. This is a focused follow-up, not a rerun or replacement of the historical
[full regression](desktop-regression-2026-10-23.md).

## Accepted scope

- Removed the redundant desktop favorite-only filter, preserving actual favorite selection,
  one pinned favorite and ordinary cards when no favorite exists.
- Custom emoji now belongs to the date line in collection, feed, favorite and details;
  empty and legacy calendar emoji leave no reserved icon space. Mini-panel placement is unchanged.
- Desktop running/finished timer deletion is adjacent to its label; the mini-panel retains
  its previous spacer and original control identifiers, including nested presets.
- Checklist/favorite writes use a window-local accepted-action queue instead of globally
  disabling controls for every local save. An accepted editor reserves ownership immediately
  and opens with the latest saved event after preceding writes.
- The product QA skill now explicitly distinguishes transition evidence from settled screenshots.

## Evidence

Final application: `/private/tmp/countdown-desktop-polish.EihQ88/Countdown Manager.app`.
Executable SHA-256: `45dbefacd9435f8fde4b851b8449f7aeae98ed08cfca78f56cde6f1bb0812cd8`.
The bundle still identifies as 1.14.1/29; it is not the published release binary.

- Strict full SwiftLint: **PASS**, zero violations; diff whitespace check: **PASS**.
- Release CoreChecks: **PASS**, `core.log` in the artifact root; relevant core sources unchanged
  by subsequent desktop-only edits, so the result was reused.
- Release UIChecks on final sources: **PASS**, `ui-checks-accepted.log` in the artifact root.
- Native desktop: **PASS 11/11**, `desktop-retry/ui-smoke-result.txt`; result markers were read,
  rather than inferring success from LaunchServices exit status.
- Mini-panel side-effect regression: **PASS 23/23**, `panel/ui-smoke-result.txt`, same executable.
- Independent source review found and closed the pending-editor hidden-window risk and nested
  timer preset-ID collisions before final acceptance. No remaining source blockers were reported.
- Fourteen native synthetic images were generated. Manifest dimensions/signatures and executable
  provenance were verified. Collection Dark, feed Light, running/finished timer and paired
  before/held-write images were visually inspected; README uses current desktop frames only.

The controlled-write native scenario checks enabled sibling controls and stable frames while
the write remains held, rapid toggle ordering and durable JSON, fresh editor Save, reserved-editor
close/compact vetoes, external editor pause/resume, failed-save rollback and explicit cancellation
of follow-up intentions. It does not infer absence of flicker from end-state assertions alone.

## Failures and retest

- Initial compilation found an absent updater dependency in the new native fixture. The fixture
  now constructs an isolated disabled updater; no production updater semantics changed.
- The restricted build environment blocked debug-symbol generation. The same local build/tests
  succeeded with approved execution outside that restriction; no product workaround was added.
- First native attempt (`desktop/`) completed ten groups, then timed out waiting for the error
  banner's missing smoke registration. Added a passive marker aligned with the existing native
  accessibility identifier; the final fresh-home run passed all eleven groups. The failed result
  and its logs remain in the artifact root, not overwritten by the successful retest.

## Boundaries

No production event data was used as a mutable fixture. No data format, Store persistence logic
or mini-panel interaction/design contract changed. The linked-panel raw capture includes an
in-progress checklist transition and is not used as a settled screenshot.

These checks observe bounded native transitions and registered actions, not every real mouse
or keyboard frame. Full external XCUITest was not repeated: the earlier Latin-input driver and
system Save-dialog acceptance gaps remain open, along with real Spaces/Dock, VoiceOver and
other manual-only surfaces described in `VERIFICATION.md`. No new release readiness claim follows.

## Local user trial

After acceptance, checked the live desktop for an active draft, preserved a private event/preferences
backup under the artifact root, then replaced only `.local-apps/Countdown Manager.app` with the tested
bundle. The earlier local bundle was retained under the artifact root for rollback. Launched normally
without test flags/home, and observed the new date-line emoji, absent filter and desktop timer IDs
in the actual window with the user's eight events. The copied executable hash matches the accepted
bundle; the production event file was byte-identical to the pre-restart backup. No production
checkboxes, events or preferences were changed as test input. `/Applications` remains untouched.
