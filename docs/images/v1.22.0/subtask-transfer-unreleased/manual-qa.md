# External manual QA — subtask transfer

Run requested by the owner on 16 November 2026. Cases were planned before feature interaction.
The QA clone has bundle ID `local.countdownmanager.subtask-manual-qa`, a separately signed copy of the tested program,
and synthetic data under `/private/tmp/countdown-manual-qa/profile`.

The prior automated fast and native smoke evidence remains separate from this external-input run.

## Planned cases

| ID | Start and ordinary UI action | Expected | Result |
| --- | --- | --- | --- |
| A1 | Desktop source pending row, open arrow | Inline form, default tomorrow, checkbox unchanged | PASS |
| A2 | Same arrow twice, another row arrow | Collapse or switch one form, no write | PASS |
| A3 | Change date/recipient, Cancel | Exact JSON bytes preserved | PASS |
| A4 | Change date then Escape | Form closes, bytes preserved | PASS |
| A5 | Checkbox/text versus separate arrow | Completion and transfer affect separate controls | PASS |
| B1 | Tomorrow has multiple recipients | Explicit recipient required | PASS |
| B2 | Choose existing recipient and confirm | Exact UUID/text moves once, neighbors retained | PASS |
| B3 | Choose empty future date and confirm | Automatic named day created with task | PASS |
| B4 | Choose full10 recipient | Reason visible, confirm disabled | PASS |
| B5 | Choose9 recipient and confirm, try next | Becomes10, next move blocked | PASS |
| B6 | Choose source date | Source excluded as recipient | PASS |
| B7 | Retained yesterday source | Pending task can move to future | PASS |
| B8 | Empty and all-completed events | No transfer arrows or 0/0 | PASS |
| B9 | Attempt past destination through native date control | Date is constrained to today/future or transfer remains blocked | PASS |
| C1 | Open transfer then event editor | Full editor cannot replace transfer | PASS |
| C2 | Open editor then transfer attempt | Transfer cannot replace editor | PASS |
| C3 | Desktop transfer then select other event | Draft closes with no write | PASS |
| C4 | Desktop transfer then close/reopen window | Draft released, normal operations resume | PASS |
| D1 | Mini disclosure collapse/expand | Hidden controls inaccessible, data preserved | PASS |
| D2 | Mini transfer hide/show | Draft date/target retained | PASS |
| D3 | Open opposite surface and return | Busy notice locates original draft | PASS |
| D4 | Mini transfer and confirm | Shared data agrees with desktop | PASS |
| D5 | Quit and relaunch isolated app | Committed changes persist | PASS |
| E1 | Rapid double confirm | Task moves once, no duplicates | PASS |
| E2 | Alternate arrows/dates/cancel and edit moved task | No stale move or wrong task ownership | PASS |
| F1 | Long task/target, observed narrow960pt desktop window | Fields/actions usable, title truncation/wrapping bounded | PASS at observed width; exact resize-limit enforcement not exercised |
| F2 | App Light/Dark setting around transfer | Existing appearance family retained | PASS |
| G1 | Test-only data folder read-only, ordinary confirm, restore permissions, retry | Error preserves source/form/durable bytes; retry moves once | PASS |

## Result

28 planned cases passed on the exercised inputs. No product defect was reproduced. No case remains pending or driver-blocked. F1 is limited to the observed narrow window; it does not establish the exact native resize clamp.

The UI driver used external CUA native click/keyboard calls and native AX `setValue` for text/date fields. It did not invoke the app smoke registry or session APIs. Keyboard cases used Command-W, Command-0, Escape and Command-Q. Date changes therefore establish native-field accessibility binding; segmented physical-key entry and every keyboard-focus path remain outside this run.

## Observations

A1–A4/B1/C1 used external native controls. The date/menu changes, Cancel and Escape left the isolated JSON byte-for-byte identical to the initial fixture. Completed row has no arrow. During open transfer, event edit/create/copy/delete buttons were disabled and source completion controls were disabled.

B2–B6/E1 used native menus and confirm buttons, including double-click confirm. Persisted JSON confirms exact A/B/C UUIDs moved to chosen recipients,9→10, unchanged full10, automatic Friday on empty20Nov, preserved completed source, and no duplicate task UUIDs. UUID string case is normalized for comparison. A5 completion then reopening is independent of arrow. C2 full editor exposes no transfer action and Cancel returns normal detail.

B7/B8/C3/C4/D1–D4/E2 passed through ordinary UI. Retained yesterday task moved to sole future receiver and retained source stayed empty. Empty/all-completed rows expose no arrows. Desktop selection and Command-W→Command-0 release idle form. Mini collapse removes hidden arrows from AX. Mini date/recipient survives Command-W then desktop busy notice→К переносу. Mini confirm moved task0 from a10-row source. Alternating task1/task2 dates and Cancel left remaining9 tasks unchanged. The moved task0 and recipient title were then edited/saved under the same identities.

D5/F1/F2/B9/G1 completed. Quit/relaunch retained moved tasks and renamed text. A50-character task wraps inside narrow desktop details; a long recipient truncates in its native picker while the full title remains in AX and actions remain reachable. The observed window screenshot was1920×1336 backing pixels, split boundary639 logical points, consistent with960pt content width. Exact minimum resize enforcement was not tested. Both explicit app Light and Dark preferences were selected through Settings and reviewed around the inline form. Attempting15Nov in the native date control constrained it to16Nov and left confirmation disabled pending an eligible selection.

G1 was added to the matrix before execution. Only the synthetic profile's CountdownManager data directory was temporarily changed to0555. Ordinary mini confirm displayed the real filesystem permission error, left the inline18Nov/recipient selection available, and preserved durable JSON bytes. Restoring0755 then ordinary confirm moved exactly one task and cleared the error. Permissions were verified restored.

A final independent comparison reconstructed all expected event/task changes from the initial fixture. All ten original events match their expected complete decoded values, including metadata, text, task order/completion and UUIDs. One ordinary automatic Friday was added. All38 original task UUIDs exist exactly once.

## Evidence and limits

- The tested source package executable SHA-256 is `df7be424e0b248225b5b02fe6f33f1ffd6166cb78d58f7b9f7df904ae2f6b285`. The QA clone's whole-file SHA-256 is `96202b367b52b876a130213999f0ae35d161e2170c2567c76788c1a769c6987d` because changing its bundle identifier and signing embeds different signature bytes. All 37 file-backed Mach-O code/data sections are identical in the [independent comparison receipt](section-comparison-original-manual.json). The historical raw `/private/tmp/countdown-manual-qa/provenance.json` field named `sourceExecutableSHA256` actually holds the clone hash; its original bytes are retained and this report corrects that naming ambiguity.
- Initial fixture, identity map and persisted result remain under `/private/tmp/countdown-manual-qa/`. They contain synthetic QA text only.
- Native screenshots were visually inspected through CUA for long-content/narrow Light/Dark states. The exposed CUA screenshot API returns image bytes without a file-save argument; this report does not claim standalone saved manual PNGs. Existing sibling capture PNGs belong to the separately documented automatic capture run.
- This was bounded exploratory testing around the transfer workflow, including row/date switching, hide/show, reverse completion, navigation and repeated confirmation. It is not an exhaustive state-space proof or an unlimited random runner.
- VoiceOver speech, Mission Control/Spaces changes, full compositor video/transient timing, every focus-navigation variant and exact minimum-window resize clamp were not exercised. No absence-of-flicker claim is made from still images.
- The isolated QA app was quit through its ordinary `Выйти` action. Production Countdown processes, data and settings were outside the manipulated surface.
- README was reviewed. This evidence-only addition changes no shipped description or application appearance, so README screenshots need no additional refresh for this pass.
