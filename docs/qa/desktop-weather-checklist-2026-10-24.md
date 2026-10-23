# Desktop checklist motion and weather geometry

2026-10-24, unreleased `codex/desktop-window`, package 1.14.1/29. This is a focused desktop fix,
not a release or another complete regression campaign. Mini-panel production code is unchanged.

## Cause and repair

- Checklist grouping already retained UUIDs but applied no animation to committed completion
  changes. The inner row container now animates reordering over 150 ms with ease-in-out. It does
  not animate the entire inspector or alter asynchronous Store/FIFO ownership. Reduce Motion
  disables the row animation transaction.
- Conditional weather changed the centered detail metadata height and selected one/two-line card
  metadata arrangements. A desktop-only 16-point forecast slot and stable separate date/weather
  rows now retain geometry with pending, unavailable, loaded or disabled forecasts. Missing
  forecasts leave empty reserved space, not fake temperatures or accessible placeholder text.
- Notes, checklist, card layout and divider must remain fixed when only forecast visibility
  changes. Different title/note lengths or deliberate window resizing can still change layout.

## Evidence

Artifacts: `/private/tmp/countdown-desktop-stability`.
Release executable SHA-256:
`1b8e5ec518983c45c0e6d510ddc23065c7eb0c379e3b61592889a6ba202544c2`.
Recorded Debug executable SHA-256:
`02931560fd6a163035c9731780466b7fc59838d21f477f2e4c58fb60202efea3`.

- Strict full SwiftLint, CoreChecks, UIChecks, release build and whitespace checks: PASS.
- Native desktop: PASS 22/22, `native/ui-smoke-result.txt`. Existing held-write, rapid-input,
  failed-save, editor, settings, split retention and monthly-layout checks remain green.
- The added gated synthetic weather fixture compares complete overview/card/identity/note/checklist
  frames through pending → loaded, missing forecast, global OFF/ON and per-event OFF/ON in both
  modes with approximately 326- and 633-point browser widths. Geometry remains within one point;
  only deliberate isolated per-event flag saves change fixture JSON. There is no public HTTP or
  native location request.
- Native normal completion/reopening and explicit Reduce Motion series retain row hosts and
  UUIDs. Their actual capture times are recorded; the first nominal 0 ms render finishes around
  64–76 ms. Cache renders and target frames alone are not proof of a compositor animation.
- Focused external XCUITest: PASS 1/1, `ChecklistMotion-valid.xcresult`,
  `checklist-focused-valid.log`. Eight tasks, five active/three completed, a valid 47-character
  wrapped label in a 320-point inspector, middle-row completion/reopening, unchanged UUID/text
  order, restored completion state and retained favorite are verified.
- QA and root reviewed actual intermediate compositor frames in both directions. The frame strips
  start at source 4.35 and 7.30 seconds with approximately 33 ms sample intervals. The application-only
  crop contains source 3.3–8.1 seconds; its clip-relative action times differ accordingly. No blank
  list frames or surrounding-section jump was observed in these two transitions. Short row/text
  crossings remain while rows swap. The source recording's 120 fps metadata is not a rendering
  throughput guarantee.
- Current native before/after weather and main README renders were visually inspected. All 64
  native PNGs, manifest dimensions/coverage, README image references and executable hash were
  verified. Safe video and intermediate strips are separate from that native manifest under
  `docs/images/v1.14.1/desktop-unreleased/weather-checklist/motion/`. Raw desktop recordings remain
  private and are not published.
- Mini-panel 23/23 evidence from the preceding settings task is intentionally reused: none of its
  production inputs changed. This is not a new mini-panel test run or an authorized mini redesign.

## Limits and rejected test attempts

Reduce Motion is checked through the isolated native owner and render series; the external
compositor recording covers normal mode only. System Reduce Motion was read as OFF and never
changed. Other OS versions/displays, VoiceOver, every intermediate frame and unrelated broad-campaign
limitations are not re-certified. This is not a claim of perfect overlap-free motion or no possible
flicker in every workflow.

An initial test-harness compile failed because the new fixture lacked its local updater stub;
that test-only reference was fixed before successful checks. The first external fixture also
exceeded the existing 50-character subtask limit and was correctly rejected by Store. Its failed
result is retained separately; the valid fixture passed without changing product validation.

## Working handoff

After the user confirmed normal Quit, the previous working bundle was backed up privately under
`/private/tmp/countdown-desktop-stability/private-backup/`. Only `.local-apps/Countdown Manager.app`
was replaced with the tested release binary. Signature and executable hash match the capture
manifest. The working copy was launched normally with no test flags/home; its exact process path
was confirmed and production event JSON remained byte-for-byte unchanged before and after launch.
The installed `/Applications` release and Git history were not modified.
