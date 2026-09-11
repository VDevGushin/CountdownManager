# Production migration scope — long-lived window shell

Status: PLANNED; implementation not authorized by the documentation-only task.
Decision: [window-shell.md](../decisions/window-shell.md)
Product contract: [PRODUCT.md](../PRODUCT.md)

## Outcome

Replace the transient shell with one ordinary window and a single internal event editor. Execute create once → show/hide without rebuilding root, list or an active draft. This scope is the implementation boundary for a subsequent explicit production task; it is not a release or installation authorization.

## 1. Shell — Sources/CountdownManager/Application.swift

- Preserve accessory startup, status title, Store ownership, diagnostics, watchdog and isolated-test configuration.
- Own one NSWindow and one NSHostingController. Create once, keep release-on-close disabled, and route native window closing to orderOut without ending the app.
- Replace togglePopover/showPopover/closePopover with show/hide of that window. If key, status-item action hides it; if hidden or not key, the action activates and brings it forward. Application reopen shows the same instance. Background/login startup leaves it hidden.
- Remove NSPopover and NSPopoverDelegate, popoverDidClose and resetTransientSession.
- Remove sheetEndObserver, local/global status-item mouse monitors, their handlers and coordinate hit-testing, isAwaitingQuickSubtaskSheetEnd, shouldDeferNextStatusItemReopen and quickSubtaskSheetRestorationRevision.
- Remove begin/stopQuickSubtaskSheetMonitoring, quickSubtaskSheetDidEnd, deferred reopen handling, restoreTransientPopoverInteraction and isTransientPopoverReady.
- Remove forced root first-responder assignment on show. Normal application/window activation remains necessary and is not a restoration mechanism.
- Adapt smoke initialization to the stable window and actual visibility; a hidden window remains non-nil.

## 2. Views — Sources/CountdownManager/Views.swift

- Retain one list hierarchy while the internal editor is open. Do not conditionally destroy the ScrollView to switch screens; keep inactive content noninteractive and inaccessible to keyboard/assistive navigation.
- Use one editing session, initialized only on explicit New/Edit. Prevent switching to another event from silently overwriting the current draft. Save success and Cancel return to the retained list; hiding does neither.
- Preserve title, note, date/countdown, emoji, primary selection, up to five subtasks, completion and validation. Keep completion and primary controls in the list.
- Remove QuickSubtaskEditorTarget, QuickSubtaskEditorView, quickSubtaskEditor state, its .sheet and callbacks. Subtask text CRUD uses the main editor.
- Replace event/subtask action popovers with explicit Edit controls and editor actions. Remove action-popover state and hover machinery used only to expose those menus.
- Embed the existing emoji catalog in the editor. Remove isEmojiPickerPresented and popup dismissal/focus coupling; do not expand the catalog or change stored emoji validation.
- Replace event deletion presentation with inline confirmation in the editor. Cancellation keeps the draft; successful deletion returns to the list; failure keeps context and displays an error.
- Present save/load errors in the primary hierarchy. Do not add new sheets/popovers for this migration.
- Expose login, diagnostics and Quit as ordinary controls; remove application action popover and Restart action.
- Remove transientDidDismiss/quickSubtaskWillPresent and popup-specific press/transition tricks. Keep ordinary field navigation/accessibility; do not remove useful FocusState merely because it exists.
- Replace the current automatic editor dismissal when its event ID expires with the PRODUCT.md unavailable-event state. Never resurrect an expired event or silently discard its draft.
- Preserve the existing visual language in a standard titled window. Keep the initial content size close to the existing 390 × 540 layout, with ordinary scrolling where needed; no anchoring to the status icon, custom chrome or animated window resizing.

## 3. Supporting state — Store.swift / Presentation.swift

- Remove Store.restart() and its external process-launch path after removal of its only product action.
- Remove quick-flow presentation helpers/strings only when no remaining caller or invariant needs them. Keep domain subtask operations unless independently proven unused; UI-flow removal is not permission for broad domain refactoring.
- Preserve Store.save and the repository boundary, asynchronous write coordination, revision ordering/rollback, refresh timers and notifications, SMAppService login integration, disclosure preferences and privacy-safe diagnostics.
- Add only the minimal in-memory state needed for the single editor's unavailable-event/error handling. No draft or navigation persistence and no schema/defaults migration.

## 4. Verification code

Affected surfaces: Sources/CountdownManager/UISmokeRuntime.swift, UISmokeControls.swift, Tests/CountdownManagerUITests/CountdownManagerUITests.swift, XCUITests/CountdownManagerXCUITests.swift and, only where selectors/scenarios require it, verify.sh and run-xcui-tests.sh.

- Replace popup readiness, nil-window teardown and sheet-restoration-revision assertions with identity/visibility/session-continuity observations.
- Update selectors and flows for direct Edit, embedded emoji selection and inline confirmation. Remove quick-sheet and action-popup-only tests; retain their meaningful CRUD/Cancel/data-safety coverage through the single editor.
- Keep synthetic data isolation, watchdog and useful regression checks. Do not add production monitors or test hooks to manufacture successful external interaction.
- Do not rewrite core tests that remain valid or preserve tests whose sole contract is the deleted workaround.

Minimum acceptance:

1. Real status-item click opens exactly one window; repeated key-window toggle hides and reopens the same hierarchy. Clicking the status item when the window is not key brings it forward.
2. Scroll down, open editor, enter unsaved text, use the native close button and separately the keyboard close command, reopen via status item. Verify root/state identity, list position, editor and draft. Continue ordinary typing without forced responder restoration.
3. With focused editor, click another app: window stays open, draft remains. Return through the status item and continue input. Repeat the hide/show paths to catch lifecycle regressions.
4. Save success persists through repository and returns to list; Cancel does not persist; write failure retains draft and existing rollback guarantees. Test only isolated storage.
5. Exercise primary selection, calendar date/countdown, note, emoji, five-subtask limit, completion and event delete/confirmation cancellation through the simplified paths.
6. Exercise expiry while editing without losing draft or recreating the event. Restart may reset transient state; stored event content and existing disclosure preferences retain their guarantees.
7. Check keyboard traversal, standard editing shortcuts and accessibility isolation of hidden list content. Verify current host and minimum supported macOS 13 where runtime is available; unavailable evidence remains explicitly unverified.

Use existing relevant CoreChecks/UIChecks for data and deterministic behaviour and targeted real-runtime/external interaction checks per docs/VERIFICATION.md. Record bundle provenance. An unavailable UI driver is a verification blocker, not a reason to substitute an internal click or build restoration code.

## 5. Documentation at implementation completion

Update ARCHITECTURE.md from pending target to actual runtime only when implemented. Update README.md usage and docs/VERIFICATION.md surface descriptions to reflect removed flows and new window checks. Keep the superseded ADR as historical evidence; record actual verification rather than implying it from ACCEPTED status.

## Out of scope

No new features, schema changes, persistence redesign, launch-at-login redesign, removal of checklist-collapse preferences, MenuBarExtra re-investigation, NSPanel variant, per-OS shell abstraction, custom event monitors, transient-state persistence, broad test/harness cleanup, or decorative redesign.

No commit, push, /Applications installation or release without separate explicit authorization. Production code is unchanged by the documentation task that created this scope.
