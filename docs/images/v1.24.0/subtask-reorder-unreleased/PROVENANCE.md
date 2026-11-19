# Subtask reorder — development screenshots

These native images are from an unreleased build on the 1.24.0/46 base, using
only isolated demonstration data. The [manifest](manifest.json) identifies the
build, screenshots, executable hash and native design contract.

## Bounded drag and balanced highlight

The current build keeps the lifted row in the original column and clamps vertical
movement to the task's completion group. It uses a soft fill with visually balanced
outer margins around the checkbox and transfer symbol. The [native run](native-result.txt)
verified diagonal input, a drop outside the checklist with the row pinned to its group,
unchanged bytes after cancellation and subsequent saved reorder flows in both windows.

The first synthetic attempt aimed outside the owning window and lost activation.
A later run sampled the outside gesture before the normal drag; its event driver
missed the next press. The current test covers movement and outside release on both
surfaces. Ordinary mouse input separately confirmed cancellation and a later reorder.

A [refreshed in-progress frame](subtask-reorder-moving.png) shows the new highlight.
The mini-panel's disclosure clip formerly cut off the highlight's leading outset.
The clip now allows the full highlight width while keeping disclosure's vertical
clipping. The [mini-panel during drag](subtask-reorder-mini-moving.png) shows the same
visible margins as the desktop row. The current native run passed both surfaces,
alongside strict SwiftLint and `verify.sh fast`.

## Original implementation acceptance

The original focused run drove mouse events through the application's native queue.
It checked the grabbed row and neighbor positions with the mouse held,
then verified one saved order on release. The desktop check measured the existing
28-point transfer target against both single-line and multiline labels. Two consecutive
mini-panel moves exercised the active and completed groups and shared desktop order.

A manual macOS run used the ordinary controls on a separate isolated copy. It checked
desktop dragging, completion toggling and transfer disclosure, two consecutive panel
moves, an out-of-group drop, the accessibility move action and return to desktop.
The first build left reorder inactive in the panel after the write settled. Observing
the existing Store from the checklist restored availability, and the repeated manual
and native scenarios passed. The original feature’s first synthetic mouse attempt had a title-bar coordinate
offset. The corrected driver targeted and moved the intended row.

[Mid-drag native capture](subtask-reorder-moving.png) shows a sampled in-progress frame.
The test observes row positions and data writes. It does not measure frame timing
or independently exercise a live system Reduce Motion change.

Before the bounded-lift refinement, the existing focused native subtask-transfer and subtask-search
checks passed 3/3 and 2/2. Strict SwiftLint and `verify.sh fast` passed.

## Completion interaction and extended QA

The previous drag mask disabled the checkbox gesture when a completion group
contained one row. The new mask preserves the native click. Ordinary pointer
testing on the isolated final product code checked the only completed and last
incomplete rows in both windows. The [extended manual QA report](manual-qa/REPORT.md)
records the original reproduction, corrected behavior, transfer and copy chains,
and the manual paths with incomplete observations.

The attached recording showed overlapping labels during mini-panel completion
regrouping near 18.5 seconds. Mini-panel grouping now updates immediately after
a completion change while drag still animates neighboring rows. The native
[before](subtask-completion-mini-before.png), [early](subtask-completion-mini-early.png)
and [saved](subtask-completion-mini-saved.png) frames show this interaction on
synthetic data. The original recording and derived private frames remain outside
repository evidence.

Native completion checks cover the render and saved-data path. Physical clicking was verified separately.
Keyboard Tab/Space behavior and system Reduce Motion changes were not verified
in the manual QA run.

## Stable layout when the transfer arrow disappears

Both checklists now reserve the arrow's footprint when a row is completed. The
desktop regression toggles a wrapped label in place and compares its frame and
the next row relative to the checklist heading, independently of window motion.
The mini-panel regression also checks that the transfer action disappears and
returns. On the isolated desktop, an ordinary pointer click and its reverse
preserved the two text lines and the position of the following task.

## Matching order in the event editor

The current [native regression results](native-regression-results.txt) cover the
checklist and editor on both surfaces. An interleaved saved checklist is reordered
in both completion groups before the native run compares text-field positions
with the expected order. The mini-panel adds and focuses a row at the end of the
incomplete group and verifies unchanged file bytes on Cancel. The desktop sheet
edits a completed row through its native field editor and verifies the saved
checklist identities, order and completion states. Strict SwiftLint and
`verify.sh fast` passed.
