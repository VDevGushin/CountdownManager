# Stable desktop application role — unreleased evidence

Date: 2026-10-23, Europe/Moscow. Branch: `codex/desktop-window`.
Research and rationale: [desktop activation and Spaces decision](../../../../decisions/desktop-activation-and-spaces.md).
The previous [compact-switch evidence](../compact-switch/PROVENANCE.md) is historical;
its policy assertions were superseded by this change, not silently reinterpreted as new evidence.

## Exact bundle

- Bundle version/build: 1.14.1/29, not the published 1.14.1 executable.
- Executable SHA-256: `98dc12fd4e6aa0357b18c57373b096e77f9c5639de291ffc3ca74cdd58993d4e`.
- Build/test work directory: `/private/tmp/countdown-native-lifecycle.SLuAeh`.
- Tested app moved to `/private/tmp/countdown-desktop-preview.udecv3/Countdown Manager.app`.
  Its moved executable was rehashed and matches the native manifest.
- CoreChecks, UIChecks and the app used the same persistent `.build` release cache and current
  source tree. `build.sh` used an isolated output path and disabled update channel.
- Native runtime launched through `open -n -W` with a marked isolated home and
  `--ui-smoke-desktop`, following the documented focused runtime mechanism.
- All eight PNGs are native 2× AppKit theme-frame renders with synthetic events and forecasts;
  they are not physical screenshots of the user's Dock or Spaces. Manifest records dimensions.
- No production event data, installed app, global Mission Control settings, commits, pushes
  or publication were changed. Earlier release and branch images are preserved.

## Acceptance

- Strict full SwiftLint and whitespace validation passed.
- `core-result.txt` and `ui-result.txt`: current release CoreChecks and UIChecks passed.
- `ui-smoke-result.txt`: native desktop PASS 8/8, with production shell callbacks enabled.
- Regression asserts menu-only accessory startup, promotion on first desktop opening, regular
  policy after close, compact transition and panel dismissal, unchanged window identity and
  timer, one-editor protection, shared checklist/favorite state and weather settings.
- Main-window configuration rejects forced-current-Space and all-Spaces flags; this establishes
  configuration only, not actual physical movement under every Mission Control setting.
- External accessibility-button input clicked the red close control on the hash-matched visual
  preview: the main window disappeared; Command-0 returned its previous selection. The current
  preview session log contains close then show with no policy demotion; no Space-change event
  was logged between those observations. This is not a full two-Space physical replay.
- Actual `В мини-панель` and `Открыть основное окно` clicks returned the expected surfaces.
- Independent review found no code blocker. Its persisted-timer documentation clarification
  was applied without changing timer semantics.

## Limits

Default switching to a Space containing the main window is deliberate native behavior, not a
promise that activation never switches Spaces. Physical two-Space/monitor/full-screen replay,
visual Dock identity and Dock click reopening are not accepted by these automated checks.
The native Dock accessibility driver timed out; this is a driver limitation, not evidence
that the Dock is missing. VoiceOver speech, older macOS/Intel and live weather remain unverified.
