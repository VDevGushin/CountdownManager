# Attachment indicators and compact section — working-source evidence

Date: 2026-10-24. Status: **unreleased working source** based on `39b4734`, still labelled
**1.15.0 / build 30**. This follow-up adds desktop card indicators and removes the duplicate
compact attachment-editor entry. It does not publish a release or install into `/Applications`.

Executable SHA-256: `2d3b46dff6fbc22a56eef38e0a5eceaf7c72edbd166c4cc85cf743dc3cefa67c`.
`manifest.json` records the eleven selected native captures and their dimensions/appearances.
`acceptance.json` records the source-input digest and the distinction between fresh and reused
evidence. The exact updater-disabled test bundle is retained at
`/private/tmp/countdown-header-weather.4egrXD/Attachment Indicators Countdown Manager.app`.

Fresh strict SwiftLint: zero violations. CoreChecks and UIChecks: PASS. The focused native
desktop route passed **25/25** on this bundle, using a marked isolated home and synthetic files,
events, forecasts, defaults and diagnostics.

The added scenario sets minimum pane width and covers:

- positive and absent indicators on ordinary and favorite cards in collection and feed;
- two files without subtasks, and two files alongside ten subtasks;
- the rendered attachment count updating from 2 to 1 after Save;
- no compact add/change action, while the desktop section retains its real editor action;
- existing editor Cancel/Save, owned-copy cleanup and original-file preservation.

Favorite fixtures are selected through Store. Native renders establish their actual favorite
and ordinary compositions; the scenario does not treat a cached outer-card role string as a
rendering assertion after reparenting. Attachment-count controls use the existing native smoke
registration path so retained SwiftUI callbacks do not certify a stale count. Earlier failed
measurement runs remain in the private temporary evidence directory.

Independent visual review inspected collection/feed and favorite/mini states in Light/Dark:
the checklist and paperclip counts remain distinct, the positive indicator is visible, no zero
indicator is drawn, compact files/footnote remain readable and the duplicate compact button is
absent. The images are `NSView.cacheDisplay` renders, not physical screenshots or motion video.
Editor and weather stills identify the same exercised bundle; their unchanged layouts reuse the
earlier acceptance rather than creating a new claim of external interaction.

The [earlier attachment evidence](../attachments-header-unreleased/PROVENANCE.md) remains valid
for unchanged Core/Store copying, persistence, expiry and editor behavior: native mini **23/23**,
editor **5/5**, collapse **2/2**, three continuity runs **8/8** and the focused external picker
workflow **1/1** on English input. Those broad and external routes were intentionally not rerun
for a conditional summary label and removal of a duplicate navigation button.

The captures do not establish full VoiceOver speech, every filename/count extreme, animation
smoothness, third-party editors/playback or large-media performance. Production event data was
not used as a mutable fixture. All previous release and attachment images were preserved.
