# Desktop month sections and view switching

2026-10-23, unreleased `codex/desktop-window`. No commit, push, merge, release or `/Applications`
installation is part of this change. Package metadata remains 1.14.1/29, not a new release.

## Scope

- Remove timer controls from the desktop only; keep the single timer, mini-panel, status item,
  completion alert and update guards.
- Partition ordinary events by month and year in both views, preserving stable date ordering,
  search and the separately pinned explicit favorite.
- Use native grid/list segments with accessible names instead of visible text labels.
- Reflow the same ordinary event UUIDs through `AnyLayout`, with a 0.2-second ease-in-out and
  no positional animation when Reduce Motion is enabled. Equal-height grid rows retain footer
  alignment. There is no duplicated event tree or text-scaling matched-geometry transform.

Apple's [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout) and
[custom layout guide](https://developer.apple.com/documentation/swiftui/composing-custom-layouts-with-swiftui)
describe identity-preserving layout switching; native measurements still require runtime checks.

## Evidence

Artifact root: `/private/tmp/countdown-monthly.8dDri3`.
Final executable SHA-256: `9a763fc4b05bd355e95bcaac47da8bd1c02592fb8b307d27be402b0cf7852500`.

- Full strict SwiftLint, shell syntax and diff checks: PASS.
- Release CoreChecks and UIChecks: PASS, including month/year boundaries, equal-date ordering,
  favorite-only/absent states, search and section identity.
- Final native desktop: PASS 19/19, `desktop-sampling/ui-smoke-result.txt`.
- Native monthly fixture: favorite precedes ordered headings; no empty favorite-only month;
  rapid mode changes, reduced-motion and live reversal preserve identities and divider position;
  search restores data; 40 additional events remain scrollable/selectable through the last month.
- The existing shared-state/editor/delete/appearance/divider checks remain green. Desktop timer
  controls are absent while shared running/finished state and panel spacing remain checked.
- Native mini-panel: PASS 23/23. This is a side-effect check, not a repeated external macOS campaign.
- Independent source review found no concrete blocker. Visual review inspected collection/feed
  in both themes, card text/footer alignment, long-list endpoints and selected transition renders.
- External CUA on a marked synthetic preview exercised compact navigation, mini timer start and
  return, native view segments, scrolling to the last month and repeated grid/list selection.
  Actual screen captures showed the final December heading above its event in both modes, not
  over earlier March cards. No production event was edited as a fixture.

## Test-driver findings

Three early desktop attempts failed at status-panel visibility before reaching the new monthly
fixture. The old working binary passed its 15/15 baseline on the same host. Logs showed a prior
panel dismissal still changing native occlusion state around a synthetic reopening. The updated
driver waits for the actual timer status-button rendering and hidden panel occlusion before this
settled-state interaction; it does not change shell policies or add a blind delay. The subsequent
two desktop runs passed 19/19. This is not acceptance of every possible rapid status-item toggle.

The first image series also exposed a driver problem: PNG capture overran nominal sample offsets,
so overdue samples ran without yielding the event loop. Cache-display images mixed target card
geometry with old heading transforms. The final driver yields on every sample and records actual
uptimes rather than treating filenames as timing proof. Final settled native images and external
screenshots have correctly placed headings. Failed/earlier attempts remain separate in the artifact
root and are not counted as successful evidence.

## Limits

`NSView.cacheDisplay` renders are not compositor recordings. Even the corrected samples can take
longer than the 200 ms animation, especially on the long list. They cannot certify every frame,
perceived smoothness, absence of every transient crossfade or immediate midflight cancellation
when the system preference alone changes. Final state and latest-choice behavior are verified;
a real-time visual motion check remains manual. VoiceOver speech, other macOS versions/scales,
real Spaces/Dock behavior and the earlier external Latin-input/Save-dialog limitations are not
re-certified by this focused task. No claim of exhaustive regression is made.

## Working build handoff

After confirming no open editor or running timer in the old working window, event JSON and
preferences were backed up in the private artifact directory, along with an archive of the old
bundle. The tested package replaced only `.local-apps/Countdown Manager.app` and reopened normally,
without test flags or an isolated home. Its executable hash matches the final manifest; the real
event JSON remained byte-for-byte unchanged and the new month headings/icons/no-timer footer were
observed. The temporary runnable test bundle was removed; logs, synthetic captures and private
rollback backups remain. `/Applications/Countdown Manager.app` was not modified.
