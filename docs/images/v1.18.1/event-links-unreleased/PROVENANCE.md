# Event links — unreleased native evidence, 2026-10-27

[Final completion: native 28/28 and external 3/3](completion/PROVENANCE.md). Earlier failures below are historical.

This is development work on `codex/event-links`, not a published version. The bundle still reports
1.18.1 / build 34. The installed application was not replaced. All event fixtures, preferences and
logs used for these checks were isolated from production data.

## Current screenshots

Six PNGs in this directory come from the current SwiftPM Release executable, built with
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` using `build.sh`, updates disabled.
`vtool -show-build` reports SDK 13.0, matching the installed executable's SDK field. The manifest
and [receipt](evidence.json) record executable/source/image hashes. The source windows use explicit
Light/Dark overrides; global appearance preferences were not changed.

- `desktop-links-light.png`, `desktop-links-dark.png`: real desktop details and the existing toolbar.
- `mini-links-light.png`, `mini-links-dark.png`: real mini-panel with two saved links.
- `editor-links-error-light.png`, `editor-links-error-dark.png`: actual editor, non-web address,
  inline explanation and disabled Save; the native trash symbol and separate Add spacing are visible.

The data is synthetic. These PNGs show native application content, not the earlier HTML mockup.
The sample date is tomorrow relative to the run date. They do not establish keyboard delivery,
screen-reader support, perceived animation smoothness or behavior on every macOS version.

## Acceptance evidence and limits

- Strict SwiftLint: zero violations in 79 files. CoreChecks/UIChecks include link validation,
  normalization, count/identity boundaries, old and malformed JSON, revision ordering, draft
  preservation, injected browser rejection, stale owner/value rejection and failed-save bytes.
- Focused native layout/error/Cancel run: **1/1**; [result](native-result.txt). The command was
  LaunchServices `open -n -W` on the built bundle with `--ui-smoke-desktop --ui-smoke-event-links`
  and a fresh home containing `.countdown-ui-smoke-environment`.
- External mini-panel workflow: **1/1**, 53.274 seconds. Real Add/trash, text entry, invalid-address
  guard, Save/Cancel, actual app relaunch and removal of the final link. This followed a separately
  recorded input-delivery failure under Russian layout. ABC was selected through the normal
  system shortcut; Russian was subsequently restored and verified with a read-only TIS query.
- External desktop workflow: **1/1**, 29.164 seconds, a different run. Real name edit, Cancel,
  reopening with the original name, Save and persisted changed name. These two successes are
  separate runs, not one 2/2 all-green suite.
- General desktop runtime: **not accepted as all-green**. An initial ordinary Release attempt
  stopped after 10 scenarios on panel activation visibility; a Debug attempt stopped after 7 on
  divider hit routing. The final ordinary Release attempt stopped after 15 waiting for an enabled
  event control, before the new links scope. Its [result](native-broad-latest-result.txt) is retained.
  No unrelated lifecycle or divider assertion was relaxed to make it pass.
- Earlier link-native diagnostics observed retained control registrations and stale/unfinished
  callbacks around close/reopen despite correct disk bytes. Those failed results are preserved.
  Native acceptance therefore covers rendering, invalid-address gating and Cancel bytes; ordinary
  Save/reopen/delete acceptance uses the external tests above. A registry action is not reported
  as proof of physical input or reliable modal completion.
- A separate marked visual-preview copy exercised the link action and launched Safari. Further
  browser inspection was stopped by the computer-use URL policy; actual page content was not
  verified. Browser rejection is covered through the injected opener, not a live-service claim.

macOS 13, VoiceOver, every input method, and a complete general desktop regression pass remain
unverified. These limits do not change the stored-event compatibility tests.

## SDK styling diagnostic

The Xcode Debug bundle was linked with SDK 27.0 and adopted different native control styling,
including the calendar/menu button. Its screenshots are not the current-product visual authority.
The ordinary Release captures above use the established styling. The creation button's source
was not modified for the links feature. Apple describes the automatic styling behavior in
[Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
