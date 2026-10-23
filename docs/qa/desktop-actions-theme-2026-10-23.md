# Desktop actions, layout stability and shared appearance

2026-10-23, Europe/Moscow. Unreleased `codex/desktop-window`; no commit, push, release or
installation in `/Applications`. Follows the earlier [refinement acceptance](desktop-polish-2026-10-23.md).

## Scope

- Desktop header: `Изменить` with a plain pencil, separate favorite and trash controls.
- Direct event deletion: named inline irreversible confirmation, Cancel, exact UUID targeting,
  duplicate-delivery protection, queued-write ordering, failed-delete rollback and last-event empty state.
- Stable right pane container: per-event identity stays inside it, preserving the native divider
  across selection, views, checklist/favorite changes, editor, settings, search, deletion and empty state.
- Ordinary collection cards align relative labels at the bottom within each row. No feed/favorite
  composition change follows this alignment.
- Shared persisted System/Light/Dark preference for desktop and mini-panel. Window-level native
  overrides leave macOS and menu-bar styling unchanged. Isolated capture overrides win without
  rewriting the stored preference. No event data migration or Store persistence change.

## Accepted evidence

Artifact root: `/private/tmp/countdown-desktop-delete.6TRiHy`.
Application executable SHA-256:
`df245e3e8e9b41f9896d4737efadba20e1a40f8b674e62c56bf9e1738576fd63`.

- Strict full SwiftLint and whitespace diff check: **PASS**.
- Release UIChecks: **PASS**, `ui-checks-final.log`, including isolated theme default, malformed/
  unknown fallback, three selections, recreation/persistence and capture-priority assertions.
- Native desktop: **PASS 14/14**, `desktop-retry/ui-smoke-result.txt`.
- Mini-panel regression: **PASS 23/23**, `panel/ui-smoke-result.txt`, same executable.
- Native divider checks set the real `NSSplitView` to 58%, 42% and 61% and repeatedly observe
  its position after the affected actions. Per-row card footer geometry includes wrapped titles
  and different forecast eligibility. Bounds protect edit/delete actions in narrow panes.
- Direct-delete checks cover unchanged bytes after Cancel, target changes, external editor guards,
  held-write ordering, clearing the selected favorite, duplicate confirms, rollback and durable empty state.
- Shared appearance checks inspect both windows and both settings hosts through Dark/Light/System,
  with three sheet captures. This is owner-to-native-render evidence, not external popup selection.
- Twenty synthetic native PNGs and their exact manifest/result were retained. All dimensions,
  signatures and executable provenance were checked; README references current inspected images.
- Independent source review found no remaining concrete blocker. Long confirmation titles are
  bounded to three lines in code; the current fixture does not prove every maximum-title layout.

## Failures retained

The initial compile exposed a missing explicit `self` in the recursive test-only native split lookup;
it was fixed. The first native run reached thirteen groups and timed out in the final empty-state
predicate: it incorrectly counted registered cards from a separate hidden test window. The final
predicate checks only the two fixture UUIDs plus its own Store/detail state; all fourteen groups
passed in a fresh home. Original logs/result under `desktop/` and `ui-checks.log` were preserved.

## Boundaries and local trial

Tests did not mutate production events/preferences. Before replacing only the local developer
bundle, checked that no real draft was active and retained fresh private data/preferences and
the previous local app under the artifact root. The new normal app was opened with the user's
current nine events and running timer; no test flags or synthetic home were used. The settings
popup was opened to show System/Light/Dark without selecting a new preference or deleting events.

This is not a full external XCUITest campaign. Physical divider dragging, macOS system-theme changes,
all sheet inheritance cases, VoiceOver and the earlier Latin-input/Save-dialog driver limits remain
manual or unaccepted as described in `VERIFICATION.md`. Passing this scope does not certify release readiness.
