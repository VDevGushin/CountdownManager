# Desktop subtask search — development evidence

Reviewed on 17 November 2026. The Product Owner accepted the interactive search prototype,
including the correction to foreground-color-only highlighting, then authorized implementation.

## Build and source

The implementation is in `codex/subtask-search`, based on main commit
`8c12c8d4683124e8b1f14df52b201cd9bf51a04a` with task-scoped working changes.
The application reports 1.23.0/45. These images show the development implementation.
The public 1.23.0 release has its own evidence in the parent directory.

The canonical `build.sh` Release path produced the exercised native bundle with updates disabled.
Executable SHA-256 is `e46a702ae447de20483166ba247ea897fde7621fef0874c3b80033a96787c933`.
Compiler SDK is macOS 27.2, the toolchain is Apple Swift 6.4.2, and deployment target and linked
compatibility are 13.0. The shared style remains `native-calendar-graphite-v2`.
The [manifest](manifest.json) records source-file hashes, packaged build provenance,
capture geometry, appearance, contrast, motion setting and each image hash.

## Acceptance

- Strict SwiftLint completed with zero violations.
- [Final `verify.sh fast` run](fast.log) passed native design/contract checks, CoreChecks and UIChecks. Search-specific
  assertions cover active/completed tasks, retained/expired events, favorite/date placement,
  duplicate prevention, trimmed case-insensitive text, Unicode, match-centered snippets,
  canonical equivalence and foreground-color attributes with inherited font metrics.
- [Focused native search acceptance](native-search-result.txt) passed 2/2 groups on this bundle.
  It edits the actual search field's native `NSTextView` editor in the explicit fixture window,
  invokes production selection/completion/favorite actions and checks rendered registry frames.
  Header, note, checklist and checkbox frames remain within 0.5 points through progressive
  title and subtask searches. Completed matches remain in the filtered collection.
- [General native desktop acceptance](native-desktop-result.txt) passed 31/31 groups on the same
  executable, including grid/feed, shared state, editor ownership, saved data, materials,
  grouping/search, retained events and native split geometry.
- The focused fixture restores its reversible completion/favorite actions and verifies byte-equal
  saved event JSON after search/clear/empty workflows. All fixture files and preferences are isolated.

The search fixture uses an injected 17 November 2026 civil date, four synthetic events,
one retained past event and checklists of up to ten tasks. Forecasts are absent in these images.

## Images

Fourteen native PNGs cover collection, feed, completed retained matches, empty results,
favorite presentation and long ten-task context in Light and Graphite Dark. The feed also has
Light and Dark Increase Contrast images. A contact-sheet review covered all fourteen, with
full-resolution inspection of the main collection, feed, favorite, completed, long and contrast
compositions. The existing cards, date leaves, field and action controls supply the UI family.
Matched text uses the existing semantic accent color and inherits its surrounding text metrics.

README uses [the current native collection](subtask-search-collection-dark.png).
Historical release images remain available in the parent directory.

## Limits and earlier attempts

Captures use `NSView.cacheDisplay` on native AppKit/SwiftUI windows with isolated appearance
overrides and Reduce Motion enabled. Physical keyboard delivery, VoiceOver speech, Spaces and
WindowServer compositor timing remain outside this acceptance.

The initial combined desktop run exited without a result and produced an `EXC_BAD_ACCESS`
report in `objc_release`; its cause remains uncertain. The final general run above completed.
Two early focused runs stopped at foreground/key-window readiness. The focused driver now
addresses its own window's field editor and checks that editor's window identity.
A subsequent attempt found an incorrect test expectation for an unregistered empty-state marker.
The final test observes the disappearance of event controls and selected details, and captures
the actual empty-result screen. These earlier attempts remain failed runs.
