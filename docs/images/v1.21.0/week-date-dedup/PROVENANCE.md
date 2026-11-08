# Week creation with occupied dates

These captures come from an unreleased fix working tree on 2026-11-08. The bundle retains
version 1.21.0 and build 42. Its executable SHA-256 is
`28102d4f670acc9b16ac3478ef4ef27a578dd8e8b522ca2f35ddd31fd89eab9e`.
The [source snapshot](source-snapshot.json) records the base commit and changed-file hashes.
[Build provenance](NativeBuildProvenance.json) records compiler SDK 15.4, linked compatibility
13.0 and the existing native-calendar-graphite-v2 style. The production updater is disabled in
this isolated development bundle.

The owner clarified that week creation must skip a full civil date occupied by any saved event.
The preview and confirmation now share the same date-only lookup. Saved title-mode and origin
metadata retain their existing encoding and editing behavior.

[Verification](verification.json) records the final CoreChecks, UIChecks and strict SwiftLint
passes, along with seven design-system and eighteen native-contract checks. The original
regression and the later ordinary-event/date-only regression each failed before their corresponding
correction. During fixture development, an intermediate Store assertion compared an unsaved empty
note with the normalized persisted value. The final assertion compares the saved baseline, and
the full final UIChecks run passed.

The [native result](ui-smoke-result.txt) passed 5/5. It exercises occupied dates in both surfaces,
an ordinary-origin automatic Monday with three preserved subtasks, a custom-titled Sunday event,
disabled creation when the only date is occupied, failed write and retry, repetition without a
write, and Sunday-to-Monday re-review. [Manifest](manifest.json) identifies the tested executable
and 24 PNGs. [File hashes](file-hashes.json) cover the copied raw evidence.

All fixtures use isolated generated events and controlled November 2026 clocks. The three README
images and selected light, dark, contrast and scrolled preview images received visual inspection.
Existing release evidence remains in its original directories. The user's diagnostics ZIP and
production events are outside this evidence archive.

This focused acceptance covers local SwiftUI preview values, rendering and persistence. External
keyboard delivery, VoiceOver speech, public update installation and WindowServer presentation timing
were outside the selected checks. Publication of this correction is a separate release step.
