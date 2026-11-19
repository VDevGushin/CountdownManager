# Desktop note visibility

The pre-fix scenario selected a word in the displayed note with AppKit mouse
events, clicked the pencil, changed the draft and cancelled. The heading and
layout remained, the note body lost its rendered pixels, and saved bytes matched.

Recreating just the selectable note text across the desktop editor's focus
handoff keeps the note visible. The focused native run exercised ten Save/Cancel
cycles with text selection, search, focus and width changes, and a subtask
reorder. It verified pixels below the heading, draft cancellation and saved text
and task order. Native subtask search passed 2/2, reordering passed 3/3, and
strict SwiftLint and fast verification passed.

The two README images came from the fixed Release executable
`0f9148d6c5fce07d218c07564992ca6e9c47dec9585eb1e4d2717fc2144a49c5`,
with isolated demonstration data. These native runs use AppKit events and
in-process captures.
