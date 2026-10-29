# Native design system and intake correction — 2026-10-28

Branch: `codex/event-links`, based on `14dc489`. Uncommitted, unpublished development; application
metadata remains 1.18.1 / build 34. This record supersedes the addition-Undo/status-row proposal.

## Accepted scope and correction

The user explicitly required removal of **addition Undo and everything in its status row**, while
retaining file/link drag-and-drop and plain-text attachments. The earlier request for auto-hide was
superseded by removing the row completely. No replacement toast, notice or timer was added.
`MaterialAdditionReceipt`, receipt/message state, Undo API, banner view and both placements were
removed. Existing error surfaces, import admission locks, editor Save/Cancel, draft-copy cleanup
and native text Undo/Redo remain. Current tests verify durable additions rather than testing the
rejected Undo behavior.

The old roadmap proposed restoring a **deleted event**, not cancelling an addition. A preselected
prototype option was not a submitted decision. Later agent-authored docs/tests could not establish
approval. See `docs/qa/product-scope-harness-2026-10-28.md` and the current feedback ledger.

## Executable native design authority

`AuroraInstrument.swift` owns the unchanged accepted warm-calendar palette and common primary,
secondary, toolbar and event-symbol action families. Save/Create, their Cancel actions, Event/Menu
and desktop/mini event actions use those components. Existing native style differences between
desktop and mini symbol actions remain explicit. Fields, material headings and disclosures retain
their named current owners; the nine-family inventory identifies them without a mass redesign.

The source gate fixes the actual accepted `AuroraInstrument` enum recipe from `14dc489`, independent
of app version and additions outside that enum. Direct mutations of RGB, shared styles, SF symbols,
toolbar labels/indicator rules and the removed status mechanic fail the same gate. These are source
contract checks, not a complete Swift AST analysis or a guarantee about every future UI change.

`NativeDesignContract.json` defines `native-warm-calendar-v1` independently of release numbers.
`build.sh` selects the compiler SDK explicitly, pins linked compatibility and records/validates
authority hashes, Mach-O metadata and signatures. Headers **SDK 15.4** and linked compatibility
**13.0** are recorded separately; this is not called a build with SDK13 headers. No vtool mutation
is used in the delivered build. Its mechanical manifest deliberately does not certify rendering.

## Verification of this corrected source

- Strict SwiftLint: zero violations; `lint-final.txt`.
- Native design source gate: **7/7**, including direct mutation rejections.
- Native build contract checks: **18/18**.
- Eval infrastructure: **36/36**; Swift hook **12/12** and native-hook infrastructure **3/3**.
- Standard `verify.sh fast`: source/build gates, CoreChecks and UIChecks **PASS**; `fast-final.txt`.
- New pure panel request checks cover visible acknowledgement, late observations, explicit hide
  and **200 rapid request sequences**.
- Exact final native desktop campaign: **28/28**; `desktop-28-final.txt`.
- Exact final material-focused campaign: **1/1**; `materials-no-status-final.txt`. It verifies
  durable local copy/original bytes and links, no addition Undo/status controls on either surface,
  fixed panel/footer geometry, collapsed sections and unchanged data after editor Cancel.
- **16 native captures** cover desktop, mini, the real mini editor and the actual composer component
  in Light/Dark × standard/Increase Contrast. Independent designer review accepted the shown states
  within the limitations below. Composer images are isolated native component fixtures; the editor
  images use the application's normal internal route. These are `NSView.cacheDisplay` observations,
  not compositor/gesture evidence.

`manifest.json` is the untouched native capture manifest. For composer fixtures its
`colorSchemeOverride` describes the **global** environment, while the fixture sets a local scheme.
`capture-appearance-annotations.json` distinguishes that global value, local fixture scheme and
actual native Aqua/DarkAqua appearance. Light fixtures are not relabelled dark because of the
global override. `delivery-desktop.png` is a separate CUA capture of the actual delivered preview.

## Historical failures and actual lifecycle fix

The first new focused run incorrectly expected a title value from an action-only registered
control. Its failure is preserved in `focused-initial-oracle-failure.txt`; the wait now checks the
enabled control and actual frame. Product behavior was not changed to satisfy that expectation.

A subsequent full native run really hid the panel after ten scenarios. The trace showed a hidden
occlusion observation arriving after a rapid new show request, without application deactivation
or Space change. This was not dismissed as a test false positive. AppDelegate now owns one
`PanelPresentationState`: a pending show first observes visibility; confirmed later full occlusion
retains the existing hide action. Explicit deactivation/Space/close routes remain immediate.
No timers, key/responder bypass, polling or hosting reconstruction were added. The previous strict
rapid hide→compact assertion was retained and the new complete campaign passed. The old failure
remains in `desktop-previous-real-occlusion-failure.txt`.

The SDK A/B diagnostic used copies with identical code and separately labelled linked metadata.
It showed a calendar-icon tint difference, but the framework's colored indicator remained at both
versions. This motivated the explicit native toolbar family/label and hidden framework indicator;
metadata alone was not declared a visual fix. Diagnostic patched copies are not delivery builds.

## Native menu and appearance limitations

Final captures show one neutral toolbar family and no colored indicator square. The decorative
SF chevron in the shared label is **not visibly rendered** by the native menu bridge in these four
desktop captures; its source presence is not counted as rendered proof. The actual preview's
accessibility role was observed as a menu button, and opening it exposed exactly the existing
`На сегодня`, `На завтра`, `Выбрать дату…` actions. No primary action was added. The independent
designer considered this residual menu-affordance limitation nonblocking for the requested style
correction; a new drawing/AppKit workaround was not introduced.

Cross-app pointer drags/status-hover cancellation, physical Space transitions, VoiceOver, every
IME and macOS13 runtime remain outside this acceptance. Earlier external gesture drivers failed
before completing those scenarios; provider/model tests are not substituted for a physical drag.

## Explicitly authorized live agent evaluations

After the automatic approval rejection, the user explicitly authorized exactly two isolated private
source/traces → Codex CLI service runs. No third run or trust/sandbox bypass was performed.

- `native-style-build-provenance`: **PASS** after independent rubric review.
- `proposal-default-is-not-acceptance`: **FAIL** for not reading the design skill and `DESIGN.md`;
  its four qualitative rubric criteria passed. The rubric does not override missing required reads.

The overall live result remains **FAIL**, preserved under
`evals/artifacts/native-style-scope-2026-10-28`. It uses the unresolved CLI-default model and is not
a controlled model comparison or statistical assurance. Required reads and scoring were not relaxed
after the result. This demonstrates that the new harness detects that boundary violation.

## Delivery and authority boundaries

New separate tester: `.build/native-design-preview/Countdown Design Preview.app`.
Archive: `.build/Countdown-Native-Design-Preview.zip`. Both use only synthetic QA-derived fixtures.
Its launcher calls LaunchServices with the adjacent marked TestData and explicit preview arguments;
native/outer signatures and the native build contract are verified. The actual preview was launched
and its menu inspected. The older tester and its now user-edited files were not replaced or used as
fixtures, cloned into this delivery, reset or redistributed.

No commit, push, main history change, production installation, release or data migration was done.


## Subsequent user manual feedback — 2026-10-28

The user requested a local preview of their own events. A separately marked personal preview was
created from the primary collection: 9 events and 11 distinct attachment folders, with source and
copy bytes compared before launch and the original JSON unchanged at that boundary. No personal
collection or attachments were included in a distribution archive, repository evidence or eval run.
The personal preview was then launched and its nine-event collection was observed.

The user's subsequent report was: «так ну я все проверил - и вроде бы работает».
This is positive, qualified overall manual feedback for the corrected build. Individual gestures
were not enumerated, so it does not independently certify every external source/physical Space/
VoiceOver/IME scenario. User edits remain in the personal preview copy; no reverse migration into
primary data was requested or performed. No application behavior changed after this report.
