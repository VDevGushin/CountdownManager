# Desktop grid/list transition repair

2026-10-23, unreleased `codex/desktop-window`. No commit, push, merge, release or `/Applications`
installation is authorized by this task. All fixtures and published captures are synthetic.

## Reported failure and cause

The user's recording is real visual failure evidence, not something settled screenshots can
dismiss. Around 8.291667 → 8.308333 seconds it changes from a full feed to a full grid in one
source-frame step. The previous implementation retained only the outer button identity while
replacing the entire inner card composition and its font sizes. Nested month stacks separately
animated their heights. Prior passing functional checks did not establish a coherent transition.

## Repair

- One flat `DesktopEventFlowLayout` places ordinary cards and month headings together.
- One `DesktopOrdinaryCardLayout` retains calendar, title, metadata, completion and remaining label.
  It no longer swaps collection/feed content trees; font sizes stay constant.
- Both layouts expose bounded scalar `animatableData`, so intermediate geometry is calculated
  every frame. Text reflows without its own glyph interpolation, inside clipped moving containers.
- The existing 0.2-second ease-in-out, Reduce Motion behavior, selection and divider rules remain.
  No timer phases, snapshots, duplicate data owner or minimum-OS change were introduced.

Apple documents [custom layout animation](https://developer.apple.com/videos/play/wwdc2022/10056/),
[per-frame animatable layout work](https://developer.apple.com/videos/play/wwdc2023/10156/?time=400)
and [leaf-local transactions](https://developer.apple.com/documentation/swiftui/view/transaction(_:)).
Runtime observation, not these references alone, determines visual acceptance.

## Verification

- Strict full SwiftLint, diff check, release CoreChecks and UIChecks: PASS.
- Final release native desktop: PASS 20/20, `/private/tmp/countdown-motion-fix/actual-native`.
  Adds stable inner-view owner checks across normal/reduced-motion mode changes; existing month,
  45-event scrolling, rapid input, footer alignment, editor, persistence and divider cases pass.
- Focused external XCUITest: PASS 1/1, zero failed/expected failures,
  `/private/tmp/countdown-motion-review/ActualLayoutMotion.xcresult`.
  Nine events across two months, long title/checklist, native controls, selection, divider,
  ordering, final-month scrolling and unchanged event bytes were checked.
- An independent reviewer and root inspected actual compositor frames in both directions. Forward
  motion is visible at 8.800–8.941667 seconds; feed is settled at 8.975. Reverse motion appears
  at 10.841667–11.016667; grid is settled at 11.050. Text remains visible and glyphs are no longer
  scrambled or stretched. The privacy-safe crop and source-frame times are retained with images.
- Existing mini-panel 23/23 evidence is reused from the previous task: shared/panel production
  code is unchanged. This is not a new full external regression campaign.

Release executable: `b4e5a19c7041b5d0613134c474b9ba6c7d1d9733a2fc6dadee5c4a63649c1a9f`.
Recorded Debug executable: `765cf7bfc8755c8cf297e3f72c0b9bd24a34879624b474e81e29d8fb04b0faef`.

## Rejected iterations and limits

The first structural repair produced actual movement but jumbled long-title glyphs. A second
leaf-transaction/clipping experiment made all labels disappear for several real source frames.
Both passed functional assertions and were rejected by recorded visual review. The explicit
animatable-layout version fixes that disappearance; the rejected variants were not installed.
Early external attempts also failed incorrect driver assumptions about the native picker role;
the permanent test now targets its actual radio-button labels. A separate full native attempt
hit the existing status-panel occlusion race after nine scenarios; it remains separate failed
evidence, not a successful run. The final current-binary desktop run passed all 20 scenarios.

This is suitable for user preview, not a claim of perfect motion: neighboring cards temporarily
occlude one another and labels can cross during their linear paths. The recording has variable
source-frame intervals and is not 60-fps performance evidence. Narrow-pane/five-column compositor
coverage, other OS versions/displays, VoiceOver and exhaustive interaction coverage remain unproven.
XCUI waits for idle between clicks; sub-200-ms retargeting is covered only by native runtime input.

## Working handoff

The old working window was inspected with no editor or running timer before normal Quit.
Events, preferences and the previous bundle were backed up privately under
`/private/tmp/countdown-motion-fix/private-backup`. The final Release package replaced only
`.local-apps/Countdown Manager.app`, reopened without test flags/home, and its executable hash
matched the retained manifest. The new interface was observed with the user's existing events;
production JSON remained byte-for-byte unchanged. Temporary runnable test bundles were removed;
recordings, result bundles, synthetic images and private rollback backups remain. The installed
`/Applications` release was not touched. No commit, push or merge followed.
