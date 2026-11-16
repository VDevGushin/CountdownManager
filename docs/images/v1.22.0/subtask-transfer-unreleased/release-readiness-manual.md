# Supplemental external release-readiness QA

The matrix was planned on 16 November 2026 after the earlier 28-case manual pass. This report preserves the later external-input observations separately from background builds, registry-driven tests and the earlier package.

## Candidate and chronology

- Initial planning used the earlier `df7be424e0b248225b5b02fe6f33f1ffd6166cb78d58f7b9f7df904ae2f6b285` package. The user then required that their adjacent-display gaming session remain uninterrupted. No supplemental UI input was issued during that restricted phase.
- The user subsequently left and authorized continuation. The parent granted a UI lease. A fresh QA clone used executable SHA-256 `b94af3e80eb384741099d3bf3aec3739151c7a7359d22eda42866b96906576f8`, identified by [readiness-candidate.json](readiness-candidate.json).
- The clone has bundle ID `local.countdownmanager.subtask-readiness-qa` and a synthetic profile under `/private/tmp/countdown-readiness-manual-qa/profile`. The source package hash above identifies the compiled program. The separately signed QA clone has whole-file SHA-256 `132340db0294e7f2418724c6144eaaf2c7f58a728f8bf6d6052c6aa6304d4393`. All 37 file-backed Mach-O sections are identical in the [b94 comparison receipt](section-comparison-b94-manual.json); the external bundle identity and embedded signature differ for LaunchServices isolation.
- The parent later prepared `0f1e4e926f09849b6d473f1df3890310990f32b1613614b36520df8ec5bb4b0b` with an explicit native open/closed accessibility value on the transfer arrow. No external result below certifies that newer package. Its focused checks remain pending.
- One CUA batch ending with `cua.getApp('com.apple.calculator')` stopped returning and was aborted after approximately 592 seconds. The parent revoked the lease to resume coordinated regression work. The last batch's partial completion is unknown. It contained no confirmation or save action, so no deactivation, status-item or Spaces success is inferred from it.

## Supplemental matrix

| ID | Start and external action | Expected | Observed result with candidate identified |
| --- | --- | --- | --- |
| K1 | Desktop pending row, keyboard-only traversal to arrow and Space | Visible focus and inline opening without completion | PASS on final A with authorized real Keyboard Navigation on. Tab reached existing controls and the arrow, and Space opened the form without completing its task. |
| K2 | Native date field reached by keyboard, segment arrows/digits | Date changes through normal key input, eligible target updates | PASS on corrected probe C. Under the same real Keyboard Navigation mode2, Tab enters the regular native date field, Up edits17→18, digits2 then0 produce20, native date segments then advance to the recipient, and Shift-Tab returns to the date. The earlier A/B failure remains documented below. |
| K3 | Keyboard recipient menu navigation and Enter/Escape | Correct choice or unchanged cancelled choice | PASS after pointer opening of the native menu. Down/Return selected QA 200. Down/Escape preserved that choice. |
| K4 | Tab/Shift-Tab to confirm and Space | Single correct move, focused controls remain distinguishable | PASS on corrected probe C for the complete changed-date route. Keyboard-only arrow Space→date Tab/Up18→recipient→Confirm Tab/Space committed the selected task to a newly created automatic day. Earlier final-A default-date confirmation also passed. |
| K5 | Full receiver then keyboard correction and Escape | Disabled confirm/reason, correction works, cancel preserves bytes | PASS. Native menu keys selected the full QA 300, the reason appeared and confirmation was disabled. Up/Return corrected to QA 200. Escape closed the form. The event file remained byte-identical to the initial fixture. |
| K6 | Mini-panel keyboard traversal and transfer/cancel | Same native semantics within compact surface | QUALIFIED on corrected probe C. Keyboard-only mini entry reaches the arrow, Tab reaches the date, and Up/Down edits18/17. Full mini confirmation was not credited because actual application deactivation hid the panel before the following Tab sequence completed; the retained draft was visible through the desktop busy notice. |
| L1 | Physical status-item opening, deactivate QA through another app, reopen | Mini hides and retains draft/selection on return | QUALIFIED. Parent used ordinary LaunchServices open -a Finder. Independent log review confirms real application deactivation and panel visible=false. Physical status-item opening remains unproven. The earlier CUA Calculator batch remains indeterminate. |
| L2 | Repeated desktop/mini navigation and alternate row selection | One transfer owner, no hidden lock or wrong-task move | PASS. Repeated mini→desktop busy notice→К переносу retained the 18 November draft. Alternating rows, collapse/expand and Escape preserved saved data. |
| L3 | Native divider dragged to both extrema with long task/receiver | Fields/actions usable, hit regions correspond to visible controls | PASS for the inspected transfer content. External screenshot-based drag changed the native divider from 639→350→320→639 logical points. The 50-character task and long recipient remained bounded and the transfer controls remained reachable at both sides. |
| L4 | Native window resize below/above legal minimum | Legal size enforced, transfer controls stay usable | UNPROVEN. Bounded corner and side-edge drag attempts caused no observable screenshot size change from 1920×1336 backing pixels. This does not distinguish an enforced size/display limit from an ineffective native resize gesture and is not marked PASS. |
| A1 | AX names/roles/enabled states for row, date/menu and confirm | Task-specific action, labelled fields, correct disabled state | PASS on final A for observed semantics. Task-specific arrow names, native field roles, disabled state and the new open/closed native value were read from actual AX state. This is not a VoiceOver speech result. |
| A2 | Mini collapse and reopen with AX inspection | Hidden form controls removed from interaction and AX | PASS through pointer disclosure actions and AX observation. The open inline form disappeared from AX when collapsed and returned with its 18 November choice intact. |
| A3 | Existing VoiceOver state and available speech delivery | Actual speech only if enabled and observable; AX alone insufficient | BLOCKED. The read-only VoiceOver preference was 0 and the tool surface has no audio observation channel. No speech PASS is inferred from correct AX labels. |
| V1 | Real Reduce Motion preference and native transfer/list transitions | Applicable motion policy on actual runtime | QUALIFIED. The actual Reduce Motion switch was turned on under user authorization and the public OS getter returned true. Transfer opening/cancel/navigation remained usable. No transition frame-timing or absence-of-flicker claim is made. |
| V2 | Real Increase Contrast preference and native transfer controls | Applicable contrast adaptation on actual runtime | PASS for the inspected real-setting adaptation. Increase Contrast was turned on through System Settings, the public getter returned true, and stronger native/card/field outlines were visually inspected. Reduce Transparency stayed false. |
| S1 | Existing Spaces accessible via native controls/shortcuts | Panel hides on Space change and stays hidden until explicit reopen | NOT EXECUTED. The status/deactivation probe did not complete before lease revocation. No Space was deliberately switched in the completed actions. |

The matrix contains **10 PASS**, **3 qualified results**, and **3 blocked or unproven results**. These are input-bound observations, not a blanket release-readiness certificate.

## Keyboard policy experiment

A read-only query returned global `AppleKeyboardUIMode = 0`. With the ordinary launch, six Tab presses stayed on Search. Six Option-Tab presses inserted literal tabs into Search. The query was restored using Command-A and Backspace.

The parent proposed a QA-only launch argument experiment. Apple documents command-line defaults as a volatile argument-domain override discarded at application exit. This supports trying a scoped override without a global write. It does not document that AppKit must honor `AppleKeyboardUIMode` from that domain. [Apple UserDefaults documentation](https://developer.apple.com/documentation/foundation/userdefaults), [Apple preference-domain guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html).

The clone was relaunched with `-AppleKeyboardUIMode 3`. Eight further Tab presses still stayed on Search. A read-only global query still returned 0. The experiment was ineffective for button traversal on this host. No production focus workaround or global keyboard preference change was applied.

## Ordinary current-candidate workflow receipt

The same b94 executable received these additional ordinary-control checks.

- QA 101 moved from QA 100 to the explicitly selected QA 200. The source retained the other pending rows and its completed row.
- QA 102 was selected for 18 November using actual native date keys. Only the synthetic data directory was temporarily set to mode 0555 before normal confirmation.
- The app displayed the real permission-denied error, kept the inline date/recipient choice, and left durable JSON byte-identical to the before-attempt snapshot.
- Permissions were restored to 0755. Pressing the same ordinary confirm moved QA 102 to QA 400 once and cleared the error.
- Cancel and keyboard Escape were exercised after date and recipient changes. Before the two deliberate transfers, all of those changes left the initial event file byte-identical.

A read-only check after lease revocation confirmed six events and all 16 original task UUIDs exactly once. QA 100 retains pending QA 103 plus completed QA 104. QA 200 contains original QA 201 plus QA 101. QA 400 contains QA 102. The full QA 300 remains at ten, the long task in QA 500 remains unchanged, and QA 600 is empty. The isolated directory permission is 0755.

A deliberate restart with post-transfer assertions was not completed on b94. A later final-A restart was completed and is documented in its phase below. The earlier planning experiment did relaunch before these transfers, which is not credited as persisted-transfer restart evidence. Focused open/cancel/move/failure-retry/restart checks on the newer package remain pending.

## Tool and evidence boundaries

All completed input used CUA native click/key/drag APIs. The date and menu cases used actual key input. No smoke registry or EventEditorSession API substituted for external input.

Native screenshots were inspected for the long-form layout and divider drags. The screenshot bytes were JPEG, with dimensions read from the JPEG frame header. An initial attempt to interpret them as PNG produced invalid dimensions and was discarded. The corrected JPEG dimensions stayed 1920×1336 across the resize attempts. No standalone saved screenshot file is claimed by this report.

The hanging batch had planned to close the long-form draft, restore the unfiltered source list, open the mini QA 103 form, choose QA 200, and then select Calculator to cause real deactivation. Its intermediate actions were not returned for observation. They are not relabelled as completed tests. Because that batch contained no confirm/save, its possible effects are limited to transient selection/search/window state.

During subsequent coordinated regression work, the parent reported a narrow desktop header overlap after three native scenes. That separate regression finding is not overridden by L3's narrower transfer-content observation and requires its own diagnosis and corrected-candidate verification.

## Current handoff

The later authorized settings/C comparison phase is complete. The UI lease has been released to the parent. All A/B/C QA processes were quit normally and their absence was checked by exact process paths. The earlier b94 process had already been quit by the parent. All temporary system settings were restored and independently reread as described below. No native input was sent outside the coordinated leases.

The newer candidate and any later geometry fix must be identified by executable hash before focused external verification resumes. Prior 28-case manual evidence remains in [manual-qa.md](manual-qa.md) with its original hash and scope. Neither earlier manual evidence nor background suites automatically satisfies the unfinished rows above.

## Parent deactivation receipt

After the interrupted CUA attempt, the parent performed a separate external activation through ordinary LaunchServices `open -a Finder`. The isolated QA log was independently read without querying or activating the QA window. It records the following sequence on 16 November 2026.

- `12:10:39.409Z` — `application-did-resign-active`, `appActive=false`, `visible=true`.
- `12:10:39.410Z` — `hide source=application-deactivation`, `requested=false`.
- `12:10:39.477Z` — `panel-occlusion-did-change`, `visible=false`, `requested=false`.

This supports actual OS application activation/deactivation and panel hiding through the external action plus native diagnostics. It does not establish a physical status-item click, composed pixels on another Space or successful delivery of the earlier Command-Tab/Finder AX-menu attempts. The parent then quit the old QA process and confirmed it absent.

The parent also reported that its XCUITest driver failed before executing tests because Apple's Automation Mode was disabled and required system authorization. This is an infrastructure/preflight limitation, with no external test pass inferred from the failed start. Subsequent native regression candidates are identified separately by the parent, including `140dd52c7a14ab88e6cf21d1b0835a2802c28ae06a8297536ae0b60178e36326`.

## Authorized temporary settings and restoration ledger

The user subsequently clarified permission to perform the required testing changes after the exact three-setting question. Temporary ordinary Keyboard Navigation, Reduce Motion and Increase Contrast changes are authorized, with restoration of their original states. The parent subsequently granted the UI lease, the actual switches were checked and changed, and all originals were restored after the bounded probes. The completed restoration receipt is linked below.

The read-only baseline was obtained through `defaults read -g AppleKeyboardUIMode` and the public NSWorkspace accessibility getters. The retained ledger is `/private/tmp/countdown-readiness-manual-qa/global-preferences-originals.json`.

| Setting | Observed original | Temporary test state | Required restoration |
| --- | --- | --- | --- |
| Ordinary Keyboard Navigation | `AppleKeyboardUIMode = 0` | On through System Settings Keyboard | Original UI state and numeric value 0 |
| Reduce Motion | false | On through the current Accessibility Motion/Display route | false |
| Increase Contrast | false | On through Accessibility Display | false |
| Reduce Transparency, possible dependent change | false | Record whether enabling contrast changes it automatically | false |

Before mutation, the actual controls and their initial values must also be read in System Settings. The intended keyboard setting is ordinary **Клавиатурная навигация**, with Tab/Shift-Tab between controls. Accessibility **Полный клавиатурный доступ** is a distinct feature and is not substituted. If AppKit keeps an old key-view policy after the setting change, relaunch only the QA clone before repeating the keyboard test.

Current Apple macOS 27 help search results place Keyboard Navigation under Keyboard, motion adjustments under Accessibility Motion, and contrast under Accessibility Display. Direct page fetching returned HTTP429, so these paths are preparation and must be verified against the actual Settings UI. [Apple Keyboard settings](https://support.apple.com/ru-ru/guide/mac-help/kbdm162/27/mac/27), [Apple motion settings](https://support.apple.com/ru-ru/guide/mac-help/mchlc03f57a1/mac), [Apple vision accessibility overview](https://support.apple.com/ru-ru/guide/mac-help/mchl67c83f41/mac).

The restoration checklist is to turn the tested controls back to their recorded originals, restore any dependent Reduce Transparency change, reread the control values and public getter/default values, and retain that verification in this report. VoiceOver is not enabled to manufacture a speech result because an audio observation channel remains unavailable. System authorization for Xcode Automation Mode remains an owner-controlled dependency.

## Authorized settings phase and ordinary final-candidate checks

After the parent granted the next UI lease, ordinary System Settings controls confirmed the original Keyboard Navigation, Reduce Motion, Increase Contrast and Reduce Transparency were all off. The three authorized test settings were then enabled through their actual controls. Read-only public getters returned Reduce Motion true and Increase Contrast true. Keyboard mode became 2. Reduce Transparency stayed false, with no dependent change.

The source package `140dd52c7a14ab88e6cf21d1b0835a2802c28ae06a8297536ae0b60178e36326` was independently compared with the running QA clone `78feec951cc0bd78c5903d6325eef8c3599177638f9587d4a789a0e6d8d52753`. All 37 file-backed sections match in [the final-manual receipt](section-comparison-final-manual.json). Whole-file differences are the expected QA identity/signature changes, so this is not a wrong-candidate finding.

On that candidate the previously host-blocked arrow became keyboard reachable. Tab moved through existing view/search/create/card/header/checkbox controls, then the transfer arrow. Space opened the form without completing the task. The arrow's native value changed from «Выбор даты закрыт» to «Выбор даты открыт». Recipient, Cancel and Confirm were reachable with Tab and Shift-Tab. Space on focused Confirm moved the selected original task to the existing next-day event, with its identity independently checked on disk.

Cancel-only date/menu experiments and ordinary editor comparison left the initial fixture byte-identical before deliberate transfers. A second task was moved to an empty18 November destination using the ordinary native date field. A real test-only filesystem permission error preserved the form and durable bytes. Restoring the directory to0755 and confirming again created an ordinary automatic «Среда» with that task. A cold ordinary restart retained all four original task UUIDs exactly once, the completed task at source and the two chosen destinations. This final-candidate success/cancel/retry/restart result is distinct from the b94 chronology above.

The actual native weather popup exposed11 entries — «Автоматически» plus Москва, Санкт-Петербург, Казань, Грозный, Нижний Новгород, Екатеринбург, Новосибирск, Самара, Ростов-на-Дону and Краснодар. Each of the10 named cities was selected through the ordinary menu and its field value checked. Москва remained selected when weather was turned off, the city field became disabled, and turning weather on retained Москва. The same off/on retention survived ordinary application restart. The QA profile used the parent's isolated synthetic weather configuration, with no production location data or real geolocation prompt used.

Real Increase Contrast was visually observed through stronger native outlines and the application card/field treatment. Real Reduce Motion was enabled at the OS and ordinary opening/cancellation/navigation remained usable. This does not measure transition frame timing or establish an absence-of-flicker claim.

## Reproduced keyboard-date defect and minimal probe B

Enabling the real keyboard-navigation setting exposed a new input defect that the earlier pointer/AX date entry did not detect. On the fresh140dd program, keyboard opening of the arrow followed by Tab skipped the inline date field and went directly to recipient, Cancel and Confirm. Reverse Shift-Tab from recipient returned to the arrow, also skipping the date. Immediate safe Up and Left/Up after opening did not change the date, with focus still on the arrow, so an unreported native date sub-responder did not explain the observation. Ctrl-Tab from the arrow also went to recipient. Mini-panel keyboard traversal reproduced the skipped date.

The existing ordinary editor was inspected as a native sibling. Tab from title entered the multiline note, where further Tab inserted literal tabs. Ctrl-Tab exited the note to the ordinary editor date field, and Up changed16 November to17 November. Cancel discarded those draft changes. This comparison does not assert that every ordinary editor Tab segment was exhaustively traversed.

The parent prepared probe B with only a Boolean FocusState property and `.focused` on the inline DatePicker, plus an unrelated unused weather-smoke helper change. The source hash is `7096250cb9ba0e13599bdd54272d1b7b639ef78dd6f4931d149efa42c625492c`; the QA-signed clone is `6297a481b436ba9670ded36d65cdf80f9360a8342aa24b0bac595b1f1d108a32`. All37 file-backed sections match its source in [the B receipt](section-comparison-focus-probe-b.json).

Probe B used a fresh identical initial fixture and the same global test values as A — keyboard2, Reduce Motion true, Increase Contrast true, Reduce Transparency false. Keyboard Tab reached the arrow and Space opened the form, then the next Tab still focused recipient and skipped the date. Reverse Shift-Tab and Ctrl-Tab reproduced the same exclusion. The two-line binding alone therefore did not fix this observed defect. Probe B was cancelled and quit without saving; its JSON remained byte-identical to its initial fixture. No extra autofocus or custom key policy was introduced by this tester.

The same three authorized global test settings were held unchanged for bounded probe C. Its actual result and the completed restoration are recorded next. The original-state ledger remained authoritative throughout; the settings were restored before releasing the UI lease.

## Corrected native date control — probe C

Probe C retained B’s focus binding and configured the inline date picker with the same native regular control size and28-point minimum height as the ordinary editor. No autofocus or custom keyboard handler was introduced. Source executable SHA-256 is `adba7e1e9e61b6cfcf8012f50f0f3e2cdf189da68663cec0fe403f3591b3aef1`, QA-clone whole-file SHA-256 is `d78a23bed626ba8abad3ea656d5036cef5ae5d71b7fb9268593039be7f299368`. Its37 file-backed code/data sections match in [the independent C receipt](section-comparison-date-control-probe-c.json).

The C clone started with a fresh copy of the same two-event initial fixture under the same actual global test values as A/B — keyboard2, Reduce Motion true, Increase Contrast true and Reduce Transparency false. This time the keyboard-only route to the arrow, Space and one Tab entered the actual inline date field. Up changed17→18 November, digits2 then0 changed the day to20, further Tab advanced through the remaining date segments to the recipient, and Shift-Tab from recipient returned to the date. This is the corrected external-input result for K2. The failed A/B observations remain above to identify the defect this configuration change resolved.

Keyboard Tab then reached Cancel and Space closed the edited form. The C event file was independently checked byte-for-byte against its initial fixture and was unchanged. A second keyboard-only run opened the arrow, entered the date, used Up to choose18 November, traversed the recipient menu and reached Confirm. Space committed the task, creating an ordinary automatic Wednesday. The source retained its other pending task and its completed task.

The mini-panel was also reached through focused footer Tab/Space. Its pending-task arrow was reached with Tab/Space, the next Tab focused the inline date, Up changed17→18 and Down restored17. The following bounded attempt to reach the recipient was interrupted by an actual application deactivation. The isolated log records `15:00:24.726Z application-did-resign-active`, followed immediately by `hide source=application-deactivation`, and `.763Z visible=false`. A later desktop view displayed the mini-transfer busy notice, consistent with retained ownership. No deliberate Space-switch key was issued by this tester, although real NSWorkspace Space-change notifications were also present during the surrounding interval. The external deactivator was not identified. Full mini confirmation is therefore uncredited, with no new application bug inferred from that interrupted route.

On the parent’s instruction, no further mini retry was attempted in the unstable external context. The C QA app was quit normally after restoring the system settings. A read-only final check confirms three C-profile events and all four initial task UUIDs once each. The transferred task is in the new18 November automatic day. The retry task and completed task remain at source, and the original17 November recipient still contains its unchanged neighbor. Thus the interrupted mini route made no additional move.

## Completed restoration and cleanup

Actual System Settings switches were returned to their observed original values. Increase Contrast was turned off, with Reduce Transparency confirmed still off. Reduce Motion was turned off in the current Accessibility Motion pane. Ordinary Keyboard Navigation was turned off. Settings was returned to its initial General section and quit. The QA app was then quit through its ordinary application shortcut.

Independent post-cleanup queries returned `AppleKeyboardUIMode = 0`, Reduce Motion false, Increase Contrast false and Reduce Transparency false, matching all four originals. Exact-path process checks found no remaining final-A, focus-B or date-control-C QA process. The retained [global settings restoration receipt](global-settings-restoration.json) has `restorationPending=false` and the observed UI/default/getter values.

No production Countdown events or preferences were used as mutable fixtures. The parent may now run its coordinated native regression suites on the frozen corrected candidate. The remaining external limitations are exact resize enforcement, a physical status-item/controlled Spaces route and VoiceOver speech/audio. The corrected keyboard-date result does not manufacture evidence for those unrelated boundaries.
