# Production migration scope — long-lived window shell

Status: SUPERSEDED 2026-09-13. The implemented standalone window failed product acceptance and was ultimately replaced by the anchored status-item panel shell. This file preserves the migration record; its target and pending gates are no longer current.
Decision: [window-shell.md](../decisions/window-shell.md)
Product contract: [PRODUCT.md](../PRODUCT.md)

## Outcome

Replace the transient shell with one utility-styled window and a single internal event editor. Execute create once → show/hide without rebuilding root, list or an active draft. The Product Owner subsequently authorized this production migration. This scope does not authorize release, commit, push or installation.

## 1. Shell — Sources/CountdownManager/Application.swift

- Preserve accessory startup, status title, Store ownership, diagnostics, watchdog and isolated-test configuration.
- Own one borderless, key-capable NSWindow subclass and one NSHostingController. Create once, keep release-on-close disabled, and route Command-W to orderOut without ending the app.
- Replace togglePopover/showPopover/closePopover with show/hide of that window. A status-item action hides it if visible, or activates and brings it forward on the active Space if hidden. Application deactivation and the native active-Space notification automatically hide it without ending the session, independently of list/editor content or responder state. Explicit Show remains authoritative until AppKit reports the application active and the retained window key. Background/login startup leaves it hidden.
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
- Preserve the existing visual language in a chrome-free utility surface backed by the same retained `NSWindow`. Keep the initial content size close to the existing 390 × 540 layout, with ordinary scrolling where needed; no anchoring to the status icon or animated window resizing.

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
2. Scroll down, open editor, enter unsaved text, use the keyboard close command, reopen via status item. Verify root/state identity, list position, editor and draft. Continue ordinary typing without forced responder restoration. Verify that the utility surface has no visible document-window title or traffic-light controls.
3. With focused editor, click another app: the window automatically hides. Return through the status item and verify the same editor/draft/list position, then continue input without responder restoration. Repeat after changing Space.
4. Save success persists through repository and returns to list; Cancel does not persist; write failure retains draft and existing rollback guarantees. Test only isolated storage.
5. Exercise primary selection, calendar date/countdown, note, emoji, five-subtask limit, completion and event delete/confirmation cancellation through the simplified paths.
6. Exercise expiry while editing without losing draft or recreating the event. Restart may reset transient state; stored event content and existing disclosure preferences retain their guarantees.
7. Check keyboard traversal, standard editing shortcuts and accessibility isolation of hidden list content. Verify current host and minimum supported macOS 13 where runtime is available; unavailable evidence remains explicitly unverified.
8. From a different active Space, click the status item and verify that the retained window moves to that Space without switching the user back to its previous Space.

Use existing relevant CoreChecks/UIChecks for data and deterministic behaviour and targeted real-runtime/external interaction checks per docs/VERIFICATION.md. Record bundle provenance. An unavailable UI driver is a verification blocker, not a reason to substitute an internal click or build restoration code.

## 5. Documentation at implementation completion

Update ARCHITECTURE.md from pending target to actual runtime only when implemented. Update README.md usage and docs/VERIFICATION.md surface descriptions to reflect removed flows and new window checks. Keep the superseded ADR as historical evidence; record actual verification rather than implying it from ACCEPTED status.

## Out of scope

No new features, schema changes, persistence redesign, launch-at-login redesign, removal of checklist-collapse preferences, MenuBarExtra re-investigation, NSPanel variant, per-OS shell abstraction, custom event monitors, transient-state persistence, broad test/harness cleanup, or decorative redesign.

No commit, push, /Applications installation or release without separate explicit authorization. Production implementation is now present in the working tree; no commit or installation has been performed.


## Verification changes in this migration

| Previous check | Disposition and reason |
| --- | --- |
| Popup close resets root and cancels a new/existing draft | Replaced with window/hosting/root State identity, editor/draft retention, continued input, and explicit Save/Cancel. The previous assertion contradicted the accepted contract. |
| Transient-popover readiness, root first responder, nil window after close | Removed. A hidden window remains allocated; focus belongs to normal controls, not to an imposed root responder. |
| Quick-subtask sheet Cancel, teardown revision and clean-root reopen (including the two dedicated XCUITests) | Removed with the sheet flow. Subtask editing/cancellation/save and completion are exercised in the single event editor. |
| Action-popover open helpers | Replaced by direct Edit controls and inline deletion confirmation. |
| Emoji-popup open/dismiss, preset-popup interaction and popup focus geometry | Replaced by embedded catalog selection and draft-field isolation. There is no secondary emoji container or separate popup geometry to verify. |
| Popup dismissal cancels pending deletion | Replaced by explicit confirmation cancellation and successful deletion; hiding no longer defines destructive-action state. |
| Root-scroll teardown/runaway regression | Replaced with repeated same-window/host/root checks, retained scroll position through editor navigation and hide/show, responsiveness and watchdog checks. |
| Visible native close-button path | Removed after visual acceptance rejected document-window chrome. The external test now proves that the close button is absent and that Command-W still hides the same retained window. |
| XCU status-item hide/reopen and Finder auto-hide assertions | Retained only as a production-shell diagnostic without the isolated lifecycle argument. The current driver cannot reliably deliver the real user action without changing activation, so it neither blocks the migration nor proves behaviour. |
| Checklist collapse/expand regression | Retained against multiple events; it protects useful behaviour independent of the shell. |
| Domain/subtask/persistence checks in CoreChecks and UIChecks | Retained, including overlapping write outcomes and legacy JSON. Added mutation-boundary coverage rejecting an existing-event edit when the event no longer exists. |

The external input fixture uses Russian text with ordinary Command-Right/Command-Delete replacement, consistent with the host's selected Russian input source. Earlier attempts to type Latin strings failed before hide/show; they are not evidence of a shell regression. The accessory app's hidden application menu is not used as an external click target. No production responder restoration was added to accommodate the driver.


## Verification results — 2026-09-12

Source base: `99e09939f0b4fdea8a3f200a95a11dca9134a288` (`origin/main`; includes the accepted shell decision from `bc65276`) plus this working-tree migration. Host: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Apple Silicon. No core model/repository format changes, production-data mutation, commit, push or `/Applications` installation.

- **CoreChecks: PASS.** Validation, calendar/Today/expiry, event/subtask ordering, limits, legacy/current JSON and repository revision checks remain green.
- **UIChecks: PASS.** Existing presentation, disclosure and overlapping persistence outcomes remain green. Added existing-event-save rejection for a missing ID, with no data file created, plus successful creation/edit and persisted-state comparison.
- **Real UI Smoke: PASS.** General scenarios 6/6, multi-event collapse regression 1/1, continuity regression 6/6 in each of three separate processes. Identity checks compare the actual window, hosting controller, content view, root State token and editor registration owner. The same NSScrollView and its position survive hiding and internal navigation. Input continues without refocusing; Save persists and Cancel discards. A forced write failure in the isolated fixture preserves draft and rollback. Removing the edited event preserves its draft and disables Save. Diagnostic privacy and watchdog checks pass.
- **External XCUITest: five retained scenarios pass.** A full run passed four and the long-list/editor-cancel scenario passed on its targeted rerun. They cover new-event Cancel isolation, borderless chrome and Command-W, long-list return position, subtask edit/cancel/save/completion and inline deletion. Status-item/auto-hide assertions were removed after the foreground-owning driver proved unable to observe production `hidesOnDeactivate` without itself triggering it.
- **Static checks: PASS.** `git diff --check`; one window/host construction site; no NSPopover, sheet flow, mouse monitors, root reconstruction or forced AppKit first-responder assignment in the shell.

### Reproducible evidence and provenance

CoreChecks/UIChecks ran through the fast portion of `./verify.sh full`. After fixing smoke timing/registration, the same `verify.sh ui` scenarios ran through a temporary copy retaining its build cache and using a fresh marked profile for every run. Its release bundle was built and ad-hoc signed from this migration immediately before execution at `/private/tmp/countdown-window-runtime/Countdown Manager.app`. Only temporary failure-output verbosity was removed afterward; runtime behaviour was unchanged.

External tests used `xcodebuild -project CountdownManager.xcodeproj -scheme CountdownManager -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/countdown-window-xcui-final-clean test`, followed by a targeted rerun of the long-list/editor-cancel scenario. Each test supplies its own marked data profile. The retained `.xcresult` files are under that DerivedData directory's `Logs/Test`.

Session-local logs (temporary evidence, not repository policy):

- `/private/tmp/countdown-window-full.log` — green CoreChecks/UIChecks; earlier smoke readiness failure subsequently fixed.
- `/private/tmp/countdown-window-runtime.log` — final green runtime smoke.
- `/private/tmp/countdown-window-xcui-final-clean/Logs/Test` — retained five-scenario XCU results; four passed together and the long-list scenario passed on targeted rerun.

The in-process registry now receives the updated enabled value explicitly and observes `.disabled` from the same environment as Save/Cancel. Smoke waits for rendered enabled controls rather than pressing immediately after a binding mutation. These correct the test surface; production does not wait for the registry.

Keyboard fixtures use the host's Russian input source; the close test sends Command plus `ц`, the character at the physical W key in that layout. The isolated automation build suppresses production deactivation and active-Space hiding so application controls stay deterministic. The separate production-shell diagnostic does not pass that lifecycle argument, but its status-item driver is not authoritative because the Finder-anchored click may not arrive and a direct XCU click activates Countdown Manager first.

### Acceptance follow-up — utility surface, Spaces, editor layout and animation

Manual product/visual acceptance confirmed scroll, editor, draft, focus/input, Save/Cancel, subtask editing, deletion and primary/menu-bar updates. It rejected the first chrome/Spaces implementation: a titled window with hidden controls still rendered ordinary title-bar chrome in the fresh release binary, and status-item activation still switched to the window's previous Space. Property-based smoke assertions did not prove those observable results.

- the retained window is now an actual `.borderless` `NSWindow` subclass whose `canBecomeKey` and `canBecomeMain` overrides preserve normal SwiftUI focus and editing;
- if the visible retained window is on another Space, the status-item show path orders it out before application activation, then makes that same instance key and front with `moveToActiveSpace` still applied;
- editor content reserves trailing clearance from the overlay scroll indicator;
- one consistent action-area gap separates scrollable form content from unavailable/delete/Save/Cancel controls;
- value-driven native SwiftUI animations cover primary-ID changes and subtask completion changes.

Relevant regression evidence after these fixes:

- **Build: PASS.** Current Swift sources compile after the borderless-window correction.
- **Real UI Smoke: PASS.** General scenarios 6/6; collapse 1/1; continuity 6/6 in each of three processes. The shell check observes the actual AppKit window state: exactly `.borderless`, no standard window-button objects, key/main eligibility, key-window activation and active-Space membership. Direct shell hide/show verifies the same window/host/root/list/editor/draft, continued input, Save and Cancel. The isolated driver disables production deactivation/occlusion hiding, so this proves session continuity after `orderOut`, not the system trigger or a real cross-Space interaction.
- **External XCUITest: PASS for the five retained scenarios.** Four passed in the final full run; the long-list/editor-cancel scenario passed on its targeted rerun. The suite covers external keyboard/button interaction, editor cancellation, subtask editing/completion and deletion. Status-item and auto-hide assertions were removed because XCUITest's foreground ownership and status-item delivery cannot reliably observe production visibility semantics.
- **Local release visual inspection: PASS as supporting evidence.** The provenance-identified bundle renders a rounded system-background surface without a title bar or traffic-light controls. Final Product Owner acceptance remains required because the previous release was rejected after lower-level checks passed.
- **Static checks: PASS.** `git diff --check` is clean; there is one window/host construction site and no popup, monitor or responder-restoration API in the production UI target.
- **Manual release acceptance: PENDING.** The fresh release bundle must visibly have no title bar or traffic lights; leaving the surface for another application or Space must hide it without losing session state; and a subsequent status-item click from Space B must keep the user on Space B while showing the existing window there. The migration is not complete until these pass.

Fresh manual bundle: `/private/tmp/countdown-window-manual-99e0993-v2/Countdown Manager.app`. It was release-built from the current working tree, ad-hoc signed and verified after the content-independent visibility correction. Executable SHA-256: `3f79fd4a3ab8b3c03d33088ac0fe35f0d2340ae77c0d127a2ba8a64f7a739abf`; modification time: `2026-09-12 20:47:46 +0300`.

### Remaining limits

- macOS 13 runtime was not available. Deployment remains macOS 13; minimum-version runtime/focus behaviour is not proven by compilation.
- No `/Applications` installation or real login-item registration was performed. Login integration itself was not changed.
- Actual midnight/wake while editing was not reproduced. Calendar expiry remains covered by existing deterministic tests; the editor's unavailable-event path was exercised by isolated event removal, and the mutation boundary rejects missing or already-expired targets.
- Window chrome has an observable AppKit-state check, but its final visual result still requires manual inspection of the provenance-identified release bundle because the previous property-only result was a false positive.
- Production auto-hide after switching applications or Spaces is not automated reliably because the UI drivers own foreground activation and generate their own occlusion transitions. Both list and editor states, confirming the old Space remains clear, and opening through the status item on the destination Space remain explicit manual acceptance requirements; `hidesOnDeactivate`, lifecycle notifications, `moveToActiveSpace`, `isOnActiveSpace`, or other property assertions are insufficient by themselves.
- Animation presence is established by the value-driven SwiftUI modifiers and the associated state changes remain functional in external tests; animation timing and Reduce Motion behaviour were not captured as visual evidence.
- Broad assistive-technology review was not performed. External tests did verify the inactive list is not hittable while editing; production additionally hides it from accessibility and disables its controls.

### Production-shell diagnostic follow-up — 2026-09-13

`./verify.sh shell` runs ten fresh Release application processes and attempts fresh launch hidden → external status-item action → observable root visible → Command-W hidden → second external status-item action → observable root visible. Any one failure fails this diagnostic command. Production diagnostics record status action, application activation/deactivation, show, occlusion change and every explicit `orderOut` source.

The known broken v2 remained RED in all ten initial runs at the first show assertion. Once action-delivery instrumentation was added, the XCU limitation became explicit: a direct status-item click activates Countdown Manager before delivery and is invalid evidence, while the Finder-anchored coordinate click does not produce `status-action` on this host. The final ten-process run therefore failed 10/10 as `PRODUCTION SHELL DRIVER`, with each lifecycle trace ending at `launch-ready`.

The working-tree production attempt moves auto-hide ownership from `hidesOnDeactivate`/occlusion to application deactivation and `NSWorkspace.activeSpaceDidChangeNotification`, and ends explicit presentation only after the application is active and the retained window is key. The XCU diagnostic has not exercised this code reliably because its external click was not delivered. It is diagnostic only and is not an acceptance stop condition. Cross-Space, real app switching and status-item activation remain manual acceptance gates.
