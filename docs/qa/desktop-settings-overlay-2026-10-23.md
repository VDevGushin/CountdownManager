# Desktop settings overlay and palette

2026-10-23, unreleased `codex/desktop-window`; package metadata remains 1.14.1/29.
No release, commit, push, merge or `/Applications` installation is part of this task.

## Accepted scope

- Keep settings centered inside the desktop window, with the original dimmed background and
  430 × 560-point pane, not a separate settings window or native settings sheet.
- Put the settings title on the left and an accessible X on the right. X, Escape and a click on
  the backdrop dismiss it; pane whitespace and controls do not. The dismissal click cannot select
  an event or manipulate the divider underneath.
- Retain the mounted desktop hierarchy, selection, split position and shared preferences.
- Apply the matching settings/editor canvas and ink at desktop hosts only. Mini-panel styling,
  Back navigation and keyboard semantics remain unchanged; shared defaults retain the old header.
- Preserve editor Save/Cancel and outside-click draft protection, diagnostic Save-sheet ownership,
  and the existing 150 ms grid/list motion.

## Evidence

Artifact root: `/private/tmp/countdown-settings-overlay`.
Final release executable SHA-256:
`925987282bdca75027309e4dadfb4869b1bb10fe14f38c7cd9951a39120beae4`.

- Full strict SwiftLint: PASS. CoreChecks: PASS; its domain inputs did not change afterward.
  Release UIChecks: PASS on final production source, including persistence and editor workflows.
  A final rebuild after the smoke-only assertion correction passed strict lint and packaging.
- Native desktop: PASS 21/21, `native-final/ui-smoke-result.txt`. Checks include the centered pane,
  absence of a separate window/settings sheet, disabled background controls, retained split
  geometry, blocked divider hits while settings are open, restored full grip routing after
  dismissal, shared appearance state and diagnostic Cancel protection.
- Mini-panel control: PASS 23/23, `mini/ui-smoke-result.txt`, with identical production code before
  the final desktop-smoke-only assertion correction. It is a side-effect check, not an interface
  redesign or a new full external regression campaign.
- Focused external XCUITest: PASS 1/1, `Final-close.xcresult` and `final-close.log`. On the final
  desktop-only production source it exercises inside header/body whitespace, a weather control,
  backdrop dismissal over a different underlying event, X, foreground Escape, retained weather,
  unchanged selection/divider/event bytes, and outside-click preservation of a dirty editor draft
  followed by Escape Cancel. Subsequent edits changed only native smoke assertions/diagnostics.
- Root visually inspected final Dark/Light settings and Light editor renders. Forty-six synthetic
  images and the exact native manifest/result are retained in
  `docs/images/v1.14.1/desktop-unreleased/settings-overlay/`; README uses this current run.
- Independent source review confirms desktop-only palette ownership and unchanged mini defaults.

## Rejected attempts and limits

The rejected standalone-settings implementation was not installed. Earlier overlay tests exposed
unreliable root `onExitCommand` routing: a controlled foreground rerun still failed Escape. The
desktop close button now uses the native cancel keyboard shortcut; the external regression passes.

The first final native run failed after seven scenarios because the old helper demanded divider
input while the new settings overlay was open. Production behavior was correct to block it. The
updated helper positively requires nonnil non-grip hits while open, preserves all geometry checks,
and retains the exact grip-hit assertions after dismissal. The final run passed all 21 scenarios;
the failed attempt remains separate under `native/`.

Native hit routing is not proof of physical divider dragging. Real Spaces/Dock, VoiceOver speech,
other macOS versions/displays, every keyboard shortcut while settings are open, and compositor
animation quality are not re-certified. The pre-existing broad-campaign Latin-input and full
diagnostics-Save limitations remain; this task checks native diagnostic Cancel, not archive Save.

## Working handoff

The tested package replaced only `.local-apps/Countdown Manager.app` after confirming no old
Countdown process remained. Its verified signature and executable hash match the final capture
manifest. It was launched normally, without test flags or an isolated home; the running process
was confirmed to originate from that exact working bundle. Real event JSON remained byte-for-byte
unchanged before and after launch. Private earlier data/preferences and bundle backups remain under
`/private/tmp/countdown-native-settings/private-backup/`. The installed `/Applications` release and
Git history remain untouched.
