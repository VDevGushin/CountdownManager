# Countdown Manager — Verification Surfaces

This file is the project-specific map of available verification commands, what they can prove, and where they stop. Product acceptance methodology lives in `.agents/skills/product-qa/SKILL.md`.

Product behaviour is defined by `docs/PRODUCT.md`. Tests are evidence for that contract, not a replacement for it.

## Commands

| Surface | Command | Cost and scope |
| --- | --- | --- |
| SwiftLint | `swiftlint lint --config .swiftlint.yml --strict --no-cache` | Fast static checks over `Sources`, `Tests`, and `XCUITests` |
| CoreChecks + UIChecks | `./verify.sh fast` | Fast deterministic regression gate |
| Real UI Smoke | `./verify.sh ui` | Release build plus isolated in-process SwiftUI/AppKit runtime scenarios |
| Desktop window Real UI Smoke | `./verify.sh desktop` | Focused isolated native desktop/panel shared-state, editor ownership, window retention and split-layout scenarios |
| Desktop window captures | `./verify.sh desktop-capture <marked-output-directory>` | The same focused desktop scenarios, retained tested app, native PNGs and executable provenance manifest |
| Attachment shelf and quick preview | `./verify.sh attachments` | Isolated native desktop/mini shelf boundaries, searchable-library return and embedded Quick Look workflows |
| Attachment captures | `./verify.sh attachments-capture <marked-output-directory>` | The same focused attachment workflows with retained tested app, native PNGs and provenance manifest |
| Editor workflows | `./verify.sh editor` | Focused native row deletion/subsequent input, field focus, Save/Cancel/reopen and weekday date changes; also included in `ui`/`full` |
| Automatic-title captures | `./verify.sh automatic-title-capture <marked-output-directory>` | Editor workflows plus six native automatic/custom title screenshots in Light/Dark/Increase Contrast, manifest and retained tested app |
| Menu identity captures | `./verify.sh menu-identity-capture <marked-output-directory>` | Focused native status-item image/title transitions, 24 isolated PNGs, packaged PDF/AppIcon checks, and retained tested bundle |
| Real panel captures | `./verify.sh capture <marked-output-directory>` | Opt-in isolated PNG evidence copied only after the capture runtime passes |
| Weather Real UI Smoke | `./verify.sh weather` | Focused isolated weather controls, shared city selection rendered natively, badges and editor persistence; actual popup input is separate XCUITest |
| Weather panel captures | `./verify.sh weather-capture <marked-output-directory>` | The focused weather/header scenarios plus ten synthetic PNGs; no general UI rerun |
| Empty-state Real UI Smoke | `./verify.sh empty-state` | Focused day creation dates/weekday defaults, Save/Cancel, retained drafts, deletion/expiry and midnight |
| Empty-state panel captures | `./verify.sh empty-state-capture <marked-output-directory>` | Same focused scenarios plus eight isolated empty/editor captures; no weather HTTP, update or general UI suite |
| Compact cards/notes | `./verify.sh compact-capture <marked-output-directory>` | Focused native note editing, 51pt cards, featured date/weather and 26 isolated PNGs |
| Completed-subtask indicator | `./verify.sh completed-subtasks-capture <marked-output-directory>` | Focused native complete/partial/zero/empty headers, disclosure transitions, Light/Dark/contrast; 16 PNGs and retained tested app |
| Combined | `./verify.sh full` | `fast`, then Real UI Smoke |
| XCUITest | `./run-xcui-tests.sh` | External keyboard and normal button interaction through Xcode |
| Native field outline guard | `python3 -B Tests/test_native_field_chrome.py` | Exercises actual SwiftLint rejection of a second outline on native rounded-border fields, plus allowed native fields and selection controls |
| Hook regression checks | `python3 -B Tests/test_swift_harness.py` | Deterministic Python hook checks; no application data or Swift builds |
| Eval runner checks | `python3 -B Tests/test_agent_evals.py` | Deterministic checks of fixtures, grading and execution; no model calls |
| Native transport checks | `python3 -B Tests/test_native_hooks.py` | Local protocol/cleanup regression checks; no Codex process or model calls |
| Update packaging checks | `python3 -B Tests/test_update_tools.py` | Feed/key/output/isolation boundaries; no production keys, application data or publication |
| Agent behaviour evals | `python3 -B evals/run.py run --model <supported-cli-model> --output evals/artifacts/<new-run>` | Opt-in isolated Codex runs plus independent checks and rubric review |
| Native Codex hooks | `python3 -B evals/native_hooks.py --model <supported-cli-model> --output evals/artifacts/<new-native-run>` | Opt-in real app-server delivery, trusted hooks, lint/fast failures and automatic repair; CLI 0.157.1 |

SwiftLint must be available on `PATH`; on macOS install it with `brew install swiftlint`.

SwiftLint also rejects direct extra `overlay`, `border` or the retired `auroraInputChrome` modifier
on a native `.roundedBorder` text-field modifier chain. The existing edit/Stop hooks enforce
this rule. Its fixtures cover rejected second outlines and allowed native fields, custom selection
controls and container borders. This source guard covers the known composition error; the
focused/unfocused visual matrix below remains necessary for native drawing and other compositions.

Codex hooks run SwiftLint only on changed Swift files after an edit. Before a Swift task completes, they run full SwiftLint and `./verify.sh fast`. Real UI Smoke and XCUITest remain evidence selected for the actual runtime risk; they are not automatic gates for unrelated Swift work.

SessionStart establishes the verification baseline. Missing, unreadable or malformed state cannot
certify a session: later hooks report a blocking diagnostic instead of silently initializing a new
baseline or treating the failure as success. A successful gate is cached against Swift contents
(including `Package.swift`) and the explicit verification dependencies: the hook implementation,
`.swiftlint.yml`, `verify.sh`, `Package.resolved`, both native-design Python test files,
`scripts/native_design_contract.py`, `Resources/NativeDesignContract.json`, and the native component
inventory JSON. Changing, adding or removing one invalidates the cached result; an unreadable
dependency blocks instead of certifying the old pass. The list in `gate_fingerprint` must grow
when the fast route gains another non-Swift dependency.
Unchanged inputs reuse the successful gate. Ordinary prose changes, including README, DESIGN
and PRODUCT, do not invalidate it. Sessions with no Swift edits still skip application checks;
harness-only work uses its focused Python tests. In a session that has already changed Swift,
a verifier change requires a fresh successful completion gate even if Swift bytes are unchanged.
This cache does not track every toolchain or environment change; rerun affected checks when those
change materially. Hook regression checks cover state failures, Stop gates, cache invalidation,
read-only calls and concurrent lifecycle calls. The cache regressions cover each named dependency,
failed-verifier rejection/retry, ordinary documentation and non-Swift sessions. They do not prove
native hook registration or trust.

The separate native hook check exercises actual `hook/started` and `hook/completed` notifications
through Codex app-server in an isolated copy. Hook script/config bytes match the reviewed repository.
Scoped SessionFlags reuse exact hashes already trusted for this project's definitions, after checking
fixture discovery and hash equality; normal runtime trust remains enforced. Global configuration is
checked byte-for-byte before and after. No bypass flags or credential copying are used.
The check observes SessionStart, read-only PostToolUse/Stop, genuine SwiftLint feedback, and a failing
CoreChecks process causing Stop feedback followed by model repair and a successful gate. A successful
gate is evidenced by completed Stop and the cache fingerprint, which is saved only after lint/fast
exit zero; successful fast stdout is not emitted by the production hook. The 2026-10-06 native run
passed and received independent artifact review. This does not test UI trust onboarding, every desktop
client configuration, or product window interaction. See `evals/README.md` for setup and limits.

Python harness/eval changes require their focused deterministic checks. Live agent evals are opt-in
when changing instructions, skills, tools or verification policy. They are not part of `verify.sh`
or the Swift completion hook. See [`evals/README.md`](../evals/README.md) for cases, artifacts, rubric
review, isolation and limitations. A successful machine check alone is `REVIEW_REQUIRED`, not PASS.

Swift behaviour evals prepare locked dependencies in a case-local SwiftPM cache before starting
the network-restricted subject. `COUNTDOWN_SWIFTPM_CACHE_PATH` makes `verify.sh fast` use that cache
with the native SwiftPM build route, locked versions and no repository updates; without it, the
normal fast command is unchanged. The native route avoids Swift Build service/dSYM sandbox failures.
Dependency preparation errors remain `INFRA_ERROR`, with separate logs, rather than a model failure.
The eval judge recognizes every listed `verify.sh` UI mode as a build/UI operation. Quiet SwiftLint
requires an unambiguous exit (standalone or in the final AND-only chain); complex shell scripts
should run it separately so skipped or masked checks cannot be credited.
Verbose lint may instead provide its real final zero-violation `Done linting!` summary.

## Native design-system gates

`./verify.sh fast` first runs `Tests/test_native_design_system.py` and
`Tests/test_native_design_contract.py`. These protect shared control families, the fixed native
identity and absence of the removed addition-Undo/status row; mutation checks demonstrate rejection
of component/palette drift. The app build uses `Resources/NativeDesignContract.json` through
`scripts/native_design_contract.py`. `build.sh` embeds actual compiler SDK/toolchain information
separately from deployment/linked compatibility and rejects mismatched metadata or authorities.
This also applies to the UI app built by verify.sh; there is no separate unverified pre-build route.

The actual headers SDK and linked compatibility are different facts. The contract retains the
accepted linked compatibility 13.0 but never relabels newer headers as SDK13. Version/build numbers
do not authorize a new identity. The script's `renderedAppearanceVerified=false` is deliberate:
only separate native captures/acceptance can establish actual appearance. Review Light/Dark and
standard/Increase Contrast against existing native siblings; a green source gate is not pixel proof.

## CoreChecks

`CoreChecks` covers behaviour without application UI:

- input validation and limits;
- date calculations and expiry;
- event and subtask ordering;
- JSON backward compatibility;
- optional weather-flag legacy decoding and true/false encoding;
- repository behaviour and persistence revision handling.

It does not prove SwiftUI rendering, AppKit lifecycle, focus, accessibility interaction, or window behaviour.

## UIChecks

`UIChecks` covers deterministic presentation and application-state behaviour:

- menu-bar and human-readable date formatting, including Russian `N событие/события/событий` endings;
- editor validity, drafts, grouping, and disclosure state;
- ordinary/day/existing weather-draft defaults and explicit Save/Cancel state;
- presentation state transitions;
- persistence coordination visible to the UI layer.

It does not prove real AppKit event routing, external keyboard delivery, system focus, application switching, or Spaces behaviour.

### Regression sequences

The ordinary `fast` gate also runs three focused workflow files:

- `RegressionSequenceChecks.swift` (CoreChecks): rejected multi-field edits preserve the complete
  snapshot/favorite; foreign, missing and deleted subtask identities preserve neighboring events;
  replacing a row in a full checklist preserves stable identities/order/completion through JSON;
  fresh repository instances preserve legacy notes/weather and subsequent expiry; validation and
  filesystem failures do not advance the accepted revision or damage existing bytes; corrupt JSON
  stays untouched after a failed read.
- `RegressionWorkflowChecks.swift` (UIChecks): multi-field edits survive a fresh Store; invalid input
  and failed writes preserve durable data before an explicit retry; removing the last subtask clears
  its collapse preference only after successful persistence; failed midnight cleanup can retry
  without changing a surviving event or its disclosure preference. Repeated row delete/add/type
  sequences preserve identities, order and completion, reject empty/whitespace replacement rows,
  and persist the final draft. Thursday/Friday transitions cover ordinary dates, year rollover and
  leap day; unchanged title commits keep new-day naming automatic, real title edits stop it, and
  ordinary/legacy titles stay explicit.
- `AsyncWorkflowRegressionChecks.swift` (UIChecks): editing a demanded date during a shared request,
  adding demand from a fresh cached batch and switching the per-event flag avoid duplicate requests;
  Moscow → Kazan → Moscow and OFF → ON keep the replacement request authoritative when the old
  generation receives HTTP 429/503. Controlled continuations and synchronous diagnostic barriers
  establish request/settlement order; deadlines fail a missing barrier rather than sequence work by
  sleeping. These one-provider ownership cases complement the existing multi-provider suite.

These checks use temporary files, separate preferences and synthetic weather; they make no native
location, public-network, process-relaunch or physical keyboard claims. The general native smoke
also covers failed Save → hide/show → explicit retry → editor reopen with title/note/subtask/favorite
intact. The three continuity runs start a timer inside an open editor, retain focus/draft and its
deadline through hide/show, Save and Cancel, then delete the timer without changing event JSON.

`editor` starts with an empty isolated store and exercises new/existing × Cancel/Save paths.
It deletes the currently focused row, types into a neighbor, adds and deletes another focused row,
then adds a fresh empty replacement and verifies Save is disabled until text is entered. Native
title/note/subtask focus handoffs and continued input after hide/show must reach the intended field.
Cancel preserves original bytes and restores a clean editor; Save preserves UUIDs, completion,
favorite, text and order through repository reload and native editor reopening. A real NSDatePicker
action verifies new-day Thursday → Friday → Thursday across title focus and hide/show. After Save,
automatic mode survives reopening, repeated custom/reset/date cycles, Cancel, a real filesystem
write failure and an explicit reset followed by successful retry. The date/title/mode and sibling
fields must match the durable snapshot.
This is in-process native input, with external keyboard delivery covered separately by XCUITest.

### Retained past events

The ordinary `fast` gate includes `RetentionChecks.swift` and `RetentionWorkflowChecks.swift`.
They exercise strict optional retention metadata, civil-day/year/leap-day boundaries, ordinary
expiry versus retained identity/primary preservation, unchanged past-date edits, rejected backdating
and stale drafts, retained legacy note/attachment allowances, actual copied bytes across restart,
failed midnight/edit/delete persistence and retry, shared ordering/grouping/search, and Russian
relative labels. All files and preferences are isolated.

The existing `desktop`/`desktop-capture` route also runs native retention workflows using an injected
civil clock and a separate isolated Store: collection/feed final past group, past favorite, mini list,
editor Save/Cancel, conditional file-lifetime explanation and uncheck → confirmation → cancel →
confirmed deletion with owned/original bytes. `desktop-capture` includes
`retention-desktop-collection-{dark,light}`, `retention-desktop-feed-{dark,light}`,
`retention-mini-list-{dark,light}` and `retention-editor-{dark,light}`. These are native synthetic
fixtures using the production views; they do not change the system clock or production data.

External XCUITest methods `testRetentionCheckboxCancelSaveAndReopen` and
`testPastRetentionUncheckConfirmsDeletionAndPreservesFilesOnCancel` exercise real checkbox/button
input, three-option order, draft cancellation, fresh launch persistence and confirmed past-event
deletion with six owned copies. They complement the controlled-clock tests; they do not establish
external date-picker editing, VoiceOver speech or physical midnight/wake timing.

### Automatic event titles

Core `AutomaticTitleChecks.swift` checks missing/false/true metadata, malformed present types and
null, omission of false, raw legacy round-trip, all weekday names, year/leap boundaries, canonical
Save, rejected past-date snapshot preservation and fresh repository/revision behavior.
UIChecks `AutomaticTitleWorkflowChecks.swift` covers day/ordinary/legacy entry routes, identical
commits, Unicode, empty/whitespace text, custom text/Undo-like restoration, explicit reset, both
directions of failed-write retry and fresh Store reload, expired/deleted identity protection, and
eight overlapping-write success/failure/completion-order combinations. Four fixed seeds each run
192 actions against an independent weekday/custom-name oracle. Every step checks draft title/mode,
Save validity, memory/disk agreement and unaffected sibling fields; failures report seed and trace.
This is 768 reproducible actions, not a claim to enumerate every possible user input.

Native `editor` exercises actual title focus, repeated custom/reset/date cycles, durable reopening,
Cancel, panel hide/show and a real isolated filesystem fault with retained draft and retry. The
`automatic-title-capture` mode also records auto/custom × Dark/Light/Light Increase Contrast, with
the native title field focused, unchanged note/task siblings, no production data or network, bundle
version/build and executable hash. It retains its tested app and result beside the six PNGs.
External XCUITests separately exercise explicit reset/Cancel/Save/reopen and native text Undo,
then repeated mode cycles with note/task UUID/favorite preservation. In-process date-picker actions
do not establish external date entry, real IME composition or VoiceOver speech.

On the 2026-10-22 host, a single `x` did not appear through targeted `typeText`, application
`typeText` or `typeKey("x", [])`, despite a focused title field. A digit and the phrase ` дописано`
were delivered. The exact same controlled sequence reproduced against an isolated archive of
pre-feature `main` commit `2933a22`, with Core/Presentation/Views verified byte-for-byte, so this is
not an automatic-title regression. The cause and real physical-keyboard behavior remain unknown;
no production menu, focus or event-routing workaround was added. The active input source was
Russian; a read-only keyboard-table query mapped physical Z to `я` (and to `z` under Command).
Permanent external edit/Undo checks use digit `1` and derive the Undo key from current layout data,
without changing the user's input source. Ordinary-title fixtures seed the original title on disk,
so only one user edit enters the native undo group. Both exact Undo/title-mode checks passed with
the current Russian/ABC mapping. Special Command layouts, IMEs and physical Latin-key delivery
remain unverified; this helper is test-driver code only.
The exploratory failures remain separate evidence, not successful runs. Apple's
[typeText contract](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typetext(_:))
requires keyboard focus; an accessibility focus snapshot alone does not prove text delivery.

Acceptance on 2026-10-22: strict SwiftLint, the full Core/UI/native gate, the final fast gate,
32 eval-runner checks, the focused capture/native workflow and six-image visual review passed.
Three unchanged external row-edit/mode-cycle cases passed in the final five-case attempt; its
two literal-key Undo cases failed, were diagnosed as above, and then passed as the focused
layout-aware two-case suite. Those earlier failures are not counted as PASS. Evidence for the
three unchanged cases is retained rather than rerunning them after a test-driver-only change.
That initial feature acceptance is historical: its preview captures retain 1.13.5/27. The 1.14.0 release has fresh exact-package native results and screenshots under docs/images/v1.14.0/.

## Mars menu identity

Run strict SwiftLint and `./verify.sh fast`, then
`./verify.sh menu-identity-capture <marked-output-directory>` after creating
`.countdown-ui-capture-output` inside that destination. The focused mode restores an expired
isolated timer at launch, exercises the actual `NSStatusBarButton`, and checks bundled vector
PDF representations rather than accepting fallback symbols. It covers Mars with empty/nonempty
unfavorited lists, K1 Today/Tomorrow, custom emoji, timer finished/running/delete restoration,
clearing/deleting favorite and durable selection reload through a fresh Store (not process relaunch). Mars uses non-template Light/Dark PDFs; K1 remains template. The focused mode also checks live appearance-only refresh and visible stripe/body colors. Panel styling is independently
asserted against the explicit favorite: no favorite leaves all rows compact. Calendar month-strip
geometry must meet the leaf's top edge at full width in both themes, for compact and featured leaves.
Core/UI checks cover invalid/expired favorites, civil boundaries, Russian labels and
persistence invariants.

The 24 PNGs comprise 16 actual native status-button cache renders, six panel captures and two
AppKit renders of the bundled Light ICNS fallback. The real opening scenario checks the status
layer's quarter/half-turn presentation transforms over one 12-second cycle, panel/desktop
triggers, timer interruption without resume, automatic completion and another opening.
It asserts that the app's Dock content view stays unchanged throughout; production code no
longer installs or redraws any custom Dock content. If the host has Reduce Motion enabled,
the scenario instead verifies suppression without changing that global preference.
Deterministic UIChecks separately cover Reduce Motion, restart/stop, unrelated animation
preservation, full-circle matrices, linear phases and center stability across layer anchors.
Light/Dark is explicitly overridden only in the isolated application; user/global appearance
settings and production data are not changed. Static PNGs render a control's model state,
not a screen recording of wallpaper compositing or live animation. Numerical presentation-layer
samples establish movement but do not prove perceived smoothness or external physical clicks.
The unchanged timer animation has its existing regression checks. The copied manifest
records version/build and executable SHA-256; the successful result and tested `.app` are retained
with the images. External status clicks, Spaces and real menu wallpaper contrast retain the manual
shell boundary below; these captures do not claim to re-prove it.

`python3 scripts/generate_icons.py` regenerates editable SVGs, native vector PDFs and the complete
ICNS size set using system Swift/CoreGraphics and `iconutil`, without Python package dependencies.
`python3 scripts/generate_icons.py --menu-only` updates only the colored Mars menu SVG/PDF pair,
without regenerating AppIcon or invoking Swift/iconutil. The generator does not read installed
application data. Native PDF drawing supplies the antialiasing; there is no PNG threshold mask
in the shipped menu images.

## Branded application icon

`python3 scripts/generate_icons.py --app-only` regenerates the two branded SVGs, ten-size
Light ICNS fallback and Icon Composer glyph layers without changing any menu resources.
`python3 scripts/compile_app_icon.py --preview` requires full Xcode 26 or newer; it compiles
`Resources/AppIcon.icon` into committed `Resources/Assets.car`, checks Aqua/Dark icon stacks
and legacy MultiSized renditions, and exports Default/Dark source previews. Normal builds
copy the catalog and ICNS fallback. The Dock icon is always static and its system presentation
is never replaced by the opening effect. Verify metadata and resource hashes in the exact
tested bundle.

Keep source previews distinct from system resolution. Icon Composer PNGs render the source
document, not the compiled CAR. A standalone AppKit probe may load the actual app through
`NSWorkspace.icon(forFile:)` and `Bundle.image(forResource:)`, render under local appearances,
and inspect brand colors/geometry; a generic nonnil image is not acceptance. These APIs may
keep the current system icon style even when drawing with DarkAqua. Do not claim a forced
Dark Finder test from two identical Default renders. Check the CAR inventory and explicit
source appearances separately. Global settings and production data must not be changed for fixtures.

## Compact cards and notes

Run full lint and `./verify.sh fast`, then `./verify.sh compact-capture <marked-output-directory>`.
This focused isolated runtime seeds genuine 151/280 legacy JSON before load; it does not use
production notes. Core/UI checks cover 150/151, Unicode graphemes/newlines, other-field/subtask/primary
saves, unchanged legacy notes, successive shorter Saves, and expired/deleted identities. Native
checks exercise NSTextView insert/selection replacement, a local pasteboard, undo, provisional/rejected
IME commit, focus into title/subtask and back, and actual native scroll geometry for empty/7+ lines.
They validate 51-point short/long headers and 28-point actions with synthetic weather, plus full-note
read/write, emoji-catalog and checklist siblings. PNGs include Light/Dark, Increase Contrast,
editor and scrolling text. Featured cases cover today weather/no-weather and long titles with −18°
in both themes, an adjacent full-date baseline and no empty separator or duplicate countdown forecast.
The same capture mode also checks Today/Tomorrow/Through 2 days in featured, short and long
cards across Light/Dark and weather ON/OFF, with twelve `relative-day-*` PNGs. Secondary relative
labels must follow the exact date on the metadata baseline. UI checks cover Russian day forms,
a saved event crossing civil midnights/year boundaries and leap-day Tomorrow. The menu-bar formatter independently uses Today/Tomorrow, then numeric day forms; the underlying Core countdown formatter is unchanged. These text/layout checks do not require repeating external note entry.
The focused XCUITests `testNewNoteHardLimitAndNativeFocus` and its Cyrillic variant target actual
keyboard 149→150→151 rejection, title/note handoff and Undo in a NEW note. In the 2026-10-23
campaign the Cyrillic route passed under the current Russian input source, but the Latin route
sent a close-command path during XCTest text synthesis and was not accepted in that run. See the
[campaign report](qa/desktop-regression-2026-10-23.md). The focused 2026-10-24 preflight on
1.15.0/30 subsequently passed the Latin limit/focus/Undo route with the user's ABC input source;
[the protocol](images/v1.15.0/preflight-input-diagnostics.json) records that source and the absence
of a clipboard fallback. This closes that route for the exercised configuration, not every input
layout. Internal native calls do not prove physical IME keyboard delivery,
VoiceOver announcements, or external keyboard routing; record those separately when exercised.
The 2026-10-20 host returned `hasMarkedText=false` and a zero-length markedRange at UTF16-end
after accepted IME commit, both in NoteTextView and in an unmodified NSTextView baseline. This
differs from Apple's documented NSNotFound sentinel. Acceptance requires exact native/draft/expected
text equality, 150 graphemes, the correct caret, no active marked text, and the same empty range as
the native baseline; it does not rewrite product composition state to satisfy a sentinel assumption.
Role-specific geometry markers avoid stale shared-calendar frames after featured/secondary changes.

## Completed-subtask indicator

After full lint and `fast`, run `completed-subtasks-capture` in a marked output directory.
The focused runtime starts with an empty isolated store and uses synthetic events only. It checks
complete/partial/zero counts through existing checkbox actions, both disclosure states, removal
of the whole header when empty, and an unfinished addition clearing the indicator before and after manual collapse.
The event's identity/date/title and primary selection persist unchanged. Disclosure geometry and
hidden checkbox input guards reuse existing checks. Presentation regression covers 0/1/6/10 totals.
Sixteen native PNGs cover Light/Dark × complete/partial/zero × expanded/collapsed, empty in each
theme, plus both contrast overrides. The mode retains its tested app, manifest and native result
beside the PNGs for independent QA. This does not establish external keyboard or VoiceOver speech;
no new input route or accessibility control is introduced by the decorative symbol.

## Desktop window

### What's new release help

`UIChecks` runs `WhatsNewChecks.swift` against two fresh UUID defaults suites: unseen reads and
an unpresented owner do not consume the release; an explicit/idempotent mark survives owner and
defaults reopening; another release and another profile retain independent history. These tests
do not by themselves prove UI admission.

The focused native route `--ui-smoke-desktop --ui-smoke-whats-new` uses a fresh marked smoke
home and the real AppDelegate/controller: no background auto-opening, pending import/editor
deferral, first safe mini opening, hidden mini while help is front, retained timer deadline,
ordinary close, no automatic repeat, manual reopen, unchanged retained editor text/Cancel and
event bytes. It requires actual 430×560 content bounds to reject native hosting shrink/clipping,
checks re-admission on close and both Settings entries (including native desktop sheet dismissal
and retained mini Settings). Four captures cover Light/Dark × standard/Increase Contrast with Reduce Motion.
The source design gate pins `whatsnew.dismiss` to `auroraPrimaryAction`; a source pass alone is
not visual acceptance. External Escape/Return/menu interaction and cross-Space behavior need
separate external input; internal registry activation is not that evidence.

### Drag and paste material intake

`UIChecks` includes `MaterialIntakeChecks.swift`: native NSItemProvider decoding priority,
exact receiving identity, local copy/original byte comparison, durable additions across ordinary
edits, full UTF-8 text round-trip (1000 lines, emoji, blank lines, trailing newline), text draft
Cancel/late-write rejection, file/link capacity rejection, failed mixed imports, failed persistence
cleanup and civil-day expiry. A deliberately delayed provider checks admission locking, duplicate
rejection, cancellation and late results not clearing a newer reservation. The same Store API checks
that scheduling reserves its operation synchronously before creating its task.

The focused native route `--ui-smoke-desktop --ui-smoke-material-intake` uses a fresh marked
smoke home. It checks persisted file/link content and both surfaces' absence of `materials.undo`
and `materials.status`, unchanged footer position, 390×600 mini dimensions and existing collapsed
sections. Its composer captures are isolated native component fixtures, not external-input proof.

Native desktop regression still covers the single sheet, inactive parent, editor ownership and
mini/desktop sibling behaviour. A native host registered for drop/context menu may return the inert
NSHostingView from hitTest while a sheet is attached; the oracle accepts only nil or that root,
rejects any divider/control hit and additionally requires background actions to be disabled.
This does not substitute a view hitTest query for a real outside click.

Focused external cases are `testFinderFileDropTargetsUnselectedEventAndPersists` and
`testSafariLinkDropCreatesOnlyWebLink`. They use their own marked test home, synthetic source file
and local HTML link; they do not use production events. Their 2026-10-28 build-for-testing passed,
but the runtime attempt stopped before test execution because system automation mode timed out.
Do not count a successfully compiled test as a successful external interaction.

Actual cross-app drags, status hover/cancel, source-app representations and ordinary Paste routing
require external input or explicit manual acceptance on an isolated tester. Never infer them from
provider unit tests. [Current evidence and limitations](images/v1.18.1/material-intake-unreleased/PROVENANCE.md).

### Event link evidence

`EventLinkChecks.swift` covers accepted HTTP/HTTPS including Unicode, rejected other schemes,
missing hosts/embedded whitespace/credentials, trim, domain fallback, 0/10/11 limits, duplicate
identities, legacy omission and malformed present JSON. Repository checks assert unchanged disk
bytes after invalid saves and stale revision rejection. `EventLinkWorkflowChecks.swift` covers
editor draft/Cancel/Save/reload, stale owner/value rejection, browser failure through an injected
opener and failed persistence retaining durable data plus the draft. These checks do not launch
an actual external browser.

`./verify.sh desktop-capture <marked-directory>` includes link layout coverage in the existing
desktop runtime: domain fallback, shared desktop/mini rendering, invalid-address inline error,
Save gating and unchanged JSON after Cancel. Mini-panel checks cover the collapsed default,
heading/count horizontal alignment, repeated disclosure, hidden-row removal from the registered
interactive hierarchy, unchanged event bytes and retained state on ordinary hide/show. Desktop checks cover zero/positive link indicators in favorite/grid/feed,
coexistence with checklist/files and containment in the existing summary host. Detail checks
assert trailing counts and value/symbol alignment for tasks, attachments and links. Twelve
`desktop-links-*`, `desktop-material-headings-*`, `editor-links-error-*`, `mini-links-*` and
`mini-links-collapsed-*` captures use
isolated Light/Dark windows. For an already built bundle, launch it
through LaunchServices with `--ui-smoke-desktop --ui-smoke-event-links` and a fresh marked smoke
home to run this scope alone; preserve executable SHA256, manifest, logs and source provenance.
Native field insertion is in-process evidence, not physical keyboard input. Do not infer reliable
reopen/Save delivery from this registry: diagnostic attempts observed retained/stale editor controls
and completion callbacks despite successful disk writes. Ordinary interactions below are the
acceptance authority for those transitions; no production lifecycle assertion was relaxed.

External case `testEventLinksEditorSaveCancelValidationAndRelaunch` uses ordinary Add/trash and
native text entry in the mini-panel: Save gating, durable address, Cancel, actual relaunch and
removing the last link. `testDesktopEventLinkCancelReopenAndSave` separately exercises desktop
name editing, Cancel/reopen with original text and Save with durable changed text.
`testMiniLinksDisclosureAtZeroOneAndTenPreservesData` checks 0/1/10 saved links, collapsed row
absence, ordinary header and trailing-count clicks, expand/collapse reversal and unchanged JSON.
Record these
runs independently, not as a combined all-green suite. Actual browser-page content, macOS 13 and
VoiceOver require their own evidence. The 2026-10-27 manual handoff launched Safari but browser
inspection was stopped by the computer-use URL policy; page content was not certified.

Build provenance matters for visual review: Xcode's current SDK-27 Debug bundle adopts different
system control styling than the SwiftPM build. `vtool -show-build` observed SDK 27.0 versus 13.0
for the reviewed Debug and ordinary Release executables. Use the ordinary `build.sh` path with
the project's SDKROOT for current-product screenshots; do not treat Debug styling as a requested
redesign. Apple documents automatic native-control changes on a new-Xcode rebuild in
[Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

The final 2026-10-27 closure passed the complete native desktop campaign **28/28** and a single
fresh external links campaign **3/3** (113.760 seconds). Before the final ABC run, a separate
Russian-layout attempt delivered punctuation instead of Latin address letters and failed 1/3;
that attempt is retained separately. CoreChecks/UIChecks additionally reject removed and expired
link clicks before the cached rendering day refreshes. The native summary sequence now asserts
value-before-symbol ordering and a shared trailing icon column for tasks/files/links.

The prior 15-scenario stop was a test-registration defect: a dynamically replaced desktop event
control used the appearance/change callback registration path and was missing/unusable in the
registry despite a saved visible favorite. Desktop event controls now use the existing native
representable registration path, which refreshes identity, action and enabled state coherently.
No product persistence/lifecycle assertions were skipped. See
[completion evidence](images/v1.18.1/event-links-unreleased/completion/PROVENANCE.md).

### Attachment evidence

#### Attachment shelf and embedded quick preview

After strict SwiftLint and `fast`, run `./verify.sh attachments` or
`./verify.sh attachments-capture <marked-output-directory>`. This uses the existing isolated
desktop runtime with an additional attachment selector, not another application-state owner.
The desktop regression route remains required for the compact detail composition and shared
window/editor behavior. When reusing an already built test bundle, preserve its executable hash,
separate marked test homes, full launch arguments, result files and stall diagnostics.

`AttachmentPreviewChecks.swift` exercises the actual transient session through controlled URL
continuations, same-ID close/reopen, stale completion, missing/non-file URL, external-action
deduplication/cancellation, independent surfaces and four reproducible seeds of 180 commands.
It checks identity/origin against an independent expected-ID oracle after each command and
compares file bytes plus canonical file inventory. `AttachmentThumbnailChecks.swift` also
requires a genuinely larger shelf raster and enforces the bounded pixel budget.

The focused native route covers saved shelves at 0/1/3/4/6/15, two/three columns, fixed canvas
and caption geometry, the mini threshold above three, saved order and existing editor/library
sizes. It scrolls the real viewport before asserting lazy cells, and uses one window coordinate
system for containment. Preview checks cover native Quick Look binding, explicit unavailable
state, navigation boundaries, retained filtered query and nonzero library scroll, source return,
current-file removal, owning-event deletion, hidden renderer release/recreation, file-tree bytes
and original preservation. A separate hosted desktop root with an injected clock exercises
expiry while its preview is open and durable cleanup with a surviving event. This is not a
test that changes the system clock or waits for a real midnight.

Focused external XCUITest cases are `testDesktopAttachmentPreviewClicksEscapeAndFilteredReturn`
and `testMiniAttachmentPreviewBackAndMissingCopyRecovery`. They perform actual file/arrow/Back
clicks, Escape, direct and library-origin backdrop clicks, search after returning, unavailable
copy recovery and byte comparisons. Internal smoke actions do not substitute for those inputs.
The same external cases exercise unmodified Left/Right navigation, first/last boundaries,
the full saved order from filtered search, and recovery from an unavailable copy in the mini-panel.
Desktop forecast geometry requires date and forecast to share a row without a middle dot,
including available, missing and disabled forecast states.

Quick Look's public host API has no content-ready/error callback: `native-preview-requested`
means a validated local URL is bound to a live renderer, not that every provider has rendered
its content. Inspect real screen captures of photo/PDF/movie content if cacheDisplay omits
service-backed pixels. `autostarts == false` and release of the old renderer's preview item
prove the resource/configuration boundary; actual manually started playback, third-party preview
extensions, VoiceOver and real app/Space switching need separately identified evidence.

CoreChecks exercises isolated file-copy ownership, backward-compatible metadata, Save/Cancel,
failed/superseded writes, active import pins, restart cleanup, expiry/deletion and symlink/path
boundaries. UIChecks adds Store draft lifetimes, partial import failures, failed Save retry,
durable expiry cleanup and refusal to bypass attachment persistence with a fake writer.
All source files, copies and preferences in these checks are temporary fixtures.

#### Native sheets, shared editor previews and favorite metadata — contract and historical 1.16.0 acceptance

Desktop Settings, file libraries and create/edit must all attach through the same native SwiftUI
sheet mechanism. Verify native attachment, usable settings/files/editor bounds, close/reopen and
native dismissal completion. Settings/files keep their cross and Escape paths; a physical click
on the parent content outside the sheet must dismiss once without activating the background,
while interior clicks keep it open. Editor outside clicks, Escape and parent close must preserve
its draft until Save/Cancel. Keep route/editor guards until native `onDismiss`, rather than using
a fixed delay or treating a retained hidden native window as an active sheet. Verify owner
removal/expiry, repeated dismissal, shared palette and native Reduce Motion behavior.

Diagnostic Save must be a nested native panel under Settings. During export, cross, Escape and
parent clicks must leave both Settings and its nested Save panel intact. Cancel/reopen must
release the export guard without changing event JSON or saved files. Native lifecycle checks
and settled screenshots do not establish physical parent clicks or compositor animation quality;
record those using an external or human interaction with its exact origin and executable.

The shared editor must show fixed 36-point preview areas after import before Save and after
reopening saved files on both surfaces. Cover photos, first-page PDF, static movie frames and at
least one provider-supported nonmedia format; a provider failure or missing preview must keep the
type fallback and usable edit actions. Every format must reach the best-effort native request,
without an image/movie whitelist. Focused Core/Store checks must protect exact draft identity,
metadata and lifetime, rejecting cancelled drafts, foreign draft files and forged metadata.
Cancel must preserve event bytes and release imported files through existing cleanup ownership.

The featured favorite's date and eligible forecast share a full-width row below title/calendar
identity. Check narrow/wide panes with pending/loaded/missing/off forecasts and unchanged selection,
divider and data. Ordinary collection-grid metadata retains its composition; current compact
details use the inline date/forecast contract in the attachment-shelf section above.
The exact `5f88a554429be8ff9aae44036ef377cd9623c7a0cd4c439eee3ab1745f716254` candidate passed
native desktop **27/27** in **52.034 seconds**, exit 0, unchanged executable and no main-thread
stall or launcher timeout. Final strict lint is **0/71**; final CoreChecks/UIChecks passed exit 0.
[Historical 1.16.0 provenance](images/v1.16.0/native-sheets/PROVENANCE.md) records 42 selected images from
110 native PNGs, exact source-manifest hash, retained failed attempts and evidence limits.
PNG/PDF/movie/TXT previews reached ready and corrupt input retained fallback in 36-point editor
areas; both mini editor themes show the files in their actual viewport. This desktop route
includes focused shared mini/editor scenarios, not a separate full mini/editor suite.
[Physical platform-probe evidence](images/v1.16.0/native-sheets/platform-probe.json) records
three consumed parent clicks and two protected-editor clicks on its separately identified
probe executable. It establishes routing on the observed runtime, not full external production
acceptance or perceived compositor fluency.

#### Desktop polish and mini disclosure — historical acceptance

The exact `69c29794d6607bc6b2a6dcae316fadfe49ceca34192061b2ce91c62e09493d2a` candidate
passed native desktop **27/27** in **55.659 seconds**, exit 0, unchanged executable hashes,
without main-thread stall or launcher timeout. Strict SwiftLint reports **0/70** and final
CoreChecks/UIChecks passed with exit 0. [Combined acceptance](images/v1.16.0/desktop-polish/acceptance.json)
keeps exact-bundle checks and reused evidence separate. [Historical provenance](images/v1.16.0/desktop-polish/PROVENANCE.md)
records 54 selected/124 full native PNGs, actual observation times, retained failed attempts
and corrected live-frame/settled-scroll driver criteria. This desktop route includes changed
shared mini attachment scenarios, not a new full mini/editor suite.

The accepted change removes saved-section editor links from populated and empty desktop
details: `Изменить список…`, `Добавить подзадачи…`, `Добавить заметку` and attachment
add/change. The header pencil must still open the shared editor with the full current event.
Focused native checks must cover populated and empty note/subtask states, no secondary entry
buttons, retained direct checkbox/file/All actions and unchanged saved event/file bytes after
Cancel. Capture populated/empty details in Light/Dark with isolated data. The shared compact
attachment component must remain free of add/change controls. Prior exact-bundle evidence below
remains explicitly historical rather than a result for the current executable.

For the historical custom Settings/files motion, the former acceptance covered opening and closing, repeated dismissal,
background input protection during closing, owner removal and Reduce Motion. That custom
overlay has been replaced by the shared native sheet. Its 200 ms timing was never evidence of
the system sheet's exact timing; settled captures alone do not prove compositor motion.
In the accepted run, requested opening offsets 0/70/260 ms were observed around 263/500/891 ms
for Settings and 331/625/1028 ms for files because cache rendering is synchronous. These samples
prove modal guards/endpoints/partial renders, not compositor fluency during the first 200 ms.
The strict long-feed viewport check waits for its final 683-point row width and three stable
document-extent observations before scrolling; it does not change application auto-scroll.

For ordinary feed layout, verify top-aligned calendar/title, upper-right remaining-time, exact
date plus forecast on the same line, and horizontal checklist/attachment summaries. Exercise
short/long titles, no/one/both summaries, narrow/wide panes and pending/loaded/missing/off
forecasts, with unchanged event ordering, selection, divider and data. Grid/favorite/detail
geometry was outside that historical redesign. The current favorite metadata follow-up is covered above.

#### Attachment overlay and mini navigation — historical acceptance

The exact `5836d97009081e079e3414f66359d602d4bad58624fd76413d7496e4448ed001`
candidate passed strict SwiftLint (0 violations in 70 files), CoreChecks/UIChecks,
native desktop 27/27 and mini 23/23 on 2026-10-25. The desktop route includes both library
surfaces, header/footer semantics, close/reopen, backdrop/pane input boundaries, retained
selection/divider, owner-removal cleanup and search states. Both native routes exited 0
with unchanged executable hashes and no main-thread stall. The
[overlay capture provenance](images/v1.16.0/attachment-overlay/PROVENANCE.md) identifies 17 new
isolated native PNGs and the exact signed-artifact audit. The separate
[external CUA receipt](images/v1.16.0/attachment-overlay/external-acceptance.json) establishes
inside-click retention, outside pointer dismissal over a different card without changing selection,
Escape from focused search, cross dismissal and mini Back/search/clear on an isolated probe
with byte-identical unsigned executable. Numeric search was entered under the English layout;
Russian filename matching is native-regression evidence. This is not full VoiceOver, first-install
or default-app-opening acceptance. The [combined receipt](images/v1.16.0/attachment-overlay/acceptance.json)
keeps these scopes separate.

#### Priority, 15-file limit and searchable libraries — historical 1.16.0 acceptance

The accepted follow-up passed fresh exact-bundle checks on 2026-10-24/25: strict SwiftLint
(0 violations in 70 files), CoreChecks/UIChecks, native desktop 27/27, mini 23/23 and editor 5/5.
[Priority/limit capture provenance](images/v1.16.0/priority-limit/PROVENANCE.md) identifies that
executable, 39 selected native PNGs and retained earlier failures. These results predate the
subsequent desktop attachment overlay change; they do not certify its dismissal behavior.
Previous RC2 results below and under `images/v1.16.0/` also remain historical evidence.

Core/Store checks must cover the 15-file limit at Save and native-picker admission: Add at
15 is unavailable, draft removal to 14 admits one new identity before Save, and a selected
batch larger than remaining capacity is rejected before any copy. Assert unchanged prior
draft/metadata/file tree for that count rejection. Keep separate I/O-failure checks that
retain earlier successful imports. Legacy collections above 15 must load without truncation
or a read error, preserve existing identities on unrelated edits and Cancel, allow removal,
and block new identities until the current draft is below 15.

The historical follow-up used the focused native `verifyAttachmentThumbnails`,
`verifyAttachmentLibrary` and `verifyRemovedDesktopLibraryOwner` scenarios for the matrix below.
Its first-four row summaries describe that accepted 1.16.0 layout. Current two/three-column
shelves, three-file mini threshold and quick-preview acceptance are documented in the
attachment-shelf section above; the 15-file storage/editor invariants remain unchanged.

The historical matrix covered:

- relative note → `Подзадачи` → `Вложения` placement in desktop details, mini cards and editor;
  consistent heading height/primary appearance and absence of the old desktop checklist label;
- stable horizontal mini attachment heading/count geometry across expanded and collapsed states,
  including a rotating disclosure chevron without a symbol-width jump;
- no saved attachment block at zero, with editor Add still available; 0/3/4/15-file cases,
  first-four summaries, 44-point desktop and 36-point mini static previews/fallbacks;
- a separate bounded read-only desktop native sheet and internal mini screen with Back, filename
  search with one match/no results/clear, and returning to the same event without changing tasks
  or event bytes; deletion/expiry of the owner closes its library on both surfaces, while hidden
  parent content cannot receive input or remain exposed to accessibility;
- desktop header `Вложение` at left and a cross at right, without Back/count; close/reopen by
  cross, Escape and backdrop, with unchanged selected event/divider and no underlying activation;
  clicks on the pane's empty interior leave it open; the native sheet is attached to the retained desktop window;
- no duplicate header count in either surface; `Файлов: N` for an empty or whitespace-only query,
  `Найдено: X из N` for a nonempty query, including zero matches; mini keeps `Вложения` and a
  plain left-chevron `Назад` control matching Settings, with its accessible Back label;
- 36-point shared editor previews before Save and after reopening, including native-preview
  success and fallback without changing import/edit/Cancel behavior;
- the editor's `N/15` counter, visible reason for disabled Add, removal/re-enable at 14, and
  Cancel preserving the saved collection; expiry explanations only in editor/delete confirmation.

Inspect Light/Dark library/all/search/empty, editor limit/order and mixed-type alignment renders.
Native dimensions and actions do not certify physical file selection, external default-app
opening or large-copy cancellation. Reuse earlier evidence only for unchanged routes, with its
source hash and remaining limitations explicitly distinguished from fresh follow-up acceptance.

The desktop runtime imports synthetic files through the real Store/repository boundary, then
checks shared desktop/mini-panel rows, editor removal with Cancel and Save, deletion of the
correct owned copies and preservation of originals. It captures both surfaces in Light/Dark.
These in-process actions do not certify physical file selection or another application's file
opening. `testAttachmentsNativePickerSaveCancelAndSharedSurfaces` separately targets the real
native open sheet, Cancel/reopen, ordinary typed file selection and shared saved-file UI; record
its actual result and input-source limits before claiming external acceptance. The external
opener, large-video performance and interruptions during filesystem copying need their own
relevant evidence; generic byte-copy checks do not prove playback or every document editor.

On 2026-10-24 the focused external scenario passed **1/1** on the user's English input source:
native picker Cancel/reopen, exact typed file path, imported copy plus editor Cancel, repeat
import plus Save, shared desktop/mini-panel file rows, removal Cancel then Save, and unchanged
original bytes. The [working-source evidence](images/v1.15.0/attachments-header-unreleased/PROVENANCE.md)
also records native desktop **24/24**, mini-panel **23/23**, editor **5/5**, collapse **2/2** and
three continuity runs **8/8** each. Earlier Russian-layout and driver/identifier failures remain
recorded as failed runs; the successful route is not certification of every input layout.

The subsequent [attachment-indicator follow-up](images/v1.15.0/attachment-indicators-unreleased/PROVENANCE.md)
passed focused native desktop **25/25**, strict lint and CoreChecks/UIChecks. Its minimum-pane
fixtures cover ordinary and favorite cards with/without files in collection/feed, attachment-only
cards, coexistence with ten subtasks, the rendered count changing 2 → 1 after Save, no compact
edit-action and the retained desktop action. Counts use native smoke registration; favorite
fixtures are set through Store and their actual card compositions are inspected in Light/Dark
renders. The previous external picker and broad mini/editor evidence is reused for unchanged
file/editor paths, not represented as a new external run for this visual-only refinement.

### Existing desktop checks

Run full SwiftLint and `./verify.sh fast` before the focused `./verify.sh desktop` runtime.
UIChecks adds deterministic desktop collection/feed presentation coverage: active-day filtering,
stable equal-date ordering, trimmed case-insensitive title/note search, favorite pinning without a favorite-only filter,
no substitute favorite for nil/invalid/expired IDs, visible selection reconciliation and
one-third/320-point pane constraints. Editor-session checks exercise exclusive panel/desktop
admission, repeated requests, wrong-owner cleanup, compatibility setters and updater postponement,
once-only resumption and termination rechecking with either editor owner.

`./verify.sh desktop` uses `--ui-smoke-desktop` with the ordinary isolated home, event file,
defaults and diagnostics boundaries. It seeds synthetic events, checklists and forecasts only.
Unlike general smoke/XCUITest modes, focused desktop smoke enables production shell lifecycle
callbacks. After native readiness, status-panel and compact-panel visibility must remain stable
through 500 ms of event processing, catching delayed activation/deactivation rather than accepting
a transient visible frame. This is a bounded temporal assertion, not a presentation delay.
The focused native scenarios exercise the retained desktop SwiftUI hierarchy in collection/feed,
shared checklist/favorite propagation between desktop and panel, no-favorite presentation,
pane geometry at minimum and larger window sizes, desktop editor Save/Cancel and durable JSON,
parent-window close veto with a draft, reverse panel-editor exclusion, settings/weather OFF,
retained desktop close/reopen, the shared timer and removed selection. This route does not
rerun the general panel regression suite; use existing focused panel checks when their shared
implementation changes.

Desktop-only refinement checks cover emoji/date metadata in browser/details, the absence of
the redundant favorite-only control and desktop timer controls, shared running/finished timer
continuity and the unchanged mini-panel timer spacer. A separate native desktop fixture holds a persistence write with a
continuation: it observes enabled controls and stable frames during that write, captures before/held
renders, accepts rapid checklist actions, then opens an editor from the latest saved snapshot.
The fixture also exercises queued-editor close/compact vetoes, external editor pause/resume and
failed-save rollback with explicit cancellation of queued follow-ups. These are bounded native
observations of the reported transient, not proof about every frame or all external interactions.

A separate synthetic monthly-browsing fixture checks ordered month/year headings, a favorite-only
month without an empty section, search empty/restored state, rapid alternating modes, Reduce Motion
and live reversal. Forty additional events exercise native scrolling, visible final-event selection
and divider retention in both modes. A content-owner regression checks that calendar, title,
metadata, completion and remaining-label hosts survive mode changes; it catches structural
replacement, not perceived smoothness. Native cache-display series record actual sample uptimes and
requested offsets around mode changes; they are not compositor recordings or proof of perceived
smoothness. Inspect intermediate renders and exercise real pointer mode switching on an isolated
preview before claiming external acceptance. The focused desktop runtime has a 65-second hard
deadline and a 70-second launch wrapper; other smoke launch timeouts remain 45 seconds.

Desktop checklist completion/reopening also captures bounded normal and Reduce Motion render
series with actual sample times and retained row hosts. Normal motion is explicitly enabled only
inside the isolated fixture; system accessibility preferences are not changed. Registry target
frames and cache-display images do not prove compositor movement. The focused external
`testDesktopChecklistMiddleRowReordersAndReturnsWithoutChangingIdentities` uses eight synthetic
tasks, including a long middle label, and checks completion/reopening, grouping and durable field
identities. Inspect its retained actual screen recording before accepting perceived row movement.

A separate gated-provider desktop fixture compares overview, ordinary/favorite card, identity,
note and checklist geometry before/after pending-to-loaded forecasts, global weather OFF/ON and
per-event weather OFF/ON. It includes an event without a forecast and both collection/feed layouts
at narrow/wide split positions. Header checks require the full current date and forecast slot
to share one row, with stable date/slot frames through pending, loaded and OFF states. Ordinary
feed rows also place date and forecast on one line; grid/favorite cards and details retain their
separate weather rows. Fixture controls use a distinct measurement namespace;
the overview header, date and weather are measured live through native view coordinates, avoiding
stale cached SwiftUI frames after divider resizing. It makes no public HTTP or location request; only explicit
per-event fixture writes change isolated JSON. This is a desktop layout check, not a change to or
re-acceptance of mini-panel weather composition.

`testDesktopGridListTransitionRetainsSelectionAndSplit` adds a focused external synthetic case
with nine events, a long title and two month headings. It checks native mode controls, selection,
divider position, ordering, final-month scrolling and unchanged event bytes. XCUI actions wait for
idle, so repeated clicks here are not sub-200-ms retargeting evidence. For animation acceptance,
retain an `.xcresult` and actual screen recordings: set `SystemAttachmentLifetime = keepAlways`
only in the generated temporary `.xctestrun` before `test-without-building`, and export attachments
with `xcrun xcresulttool export attachments`. Do not alter global Xcode/macOS settings. Review
source video frames in both directions, not just settled attachments or functional PASS. Record
the tested Debug/Release executable hash; crop to the synthetic application before publishing any
recording because raw macOS test videos can include other personal desktop content.

Direct-delete coverage checks request/Cancel without file changes, confirmation tied to the
selected UUID, duplicate delivery, favorite cleanup, deletion after a held earlier write,
failed-delete rollback and durable empty state after the last deletion. The detail header's
edit/delete action bounds are checked in narrow and larger windows. The suite sets the actual
native `NSSplitView` divider to nondefault legal positions and checks retention across selection,
mutation, mode/search, editor/settings, deletion and empty-state transitions. Collection cards
with different titles/forecast eligibility are checked for bottom-aligned relative labels.

Favorite-action palette checks inspect rendered icon regions for selected/unselected events in
Dark and Light captures. The filled star must contain accent pixels, while the outline star,
pencil and trash must contain primary-ink pixels. Channel tolerance accounts for native display
profile conversion; the neutral/accent palettes remain separated. This verifies rendered state
roles, not exact cross-display screenshot color equivalence.

Appearance preference checks cover default/fallback values, persistence and isolated capture
override priority. Native desktop smoke switches the shared owner through Dark/Light/System,
observes the desktop, mini-panel and centered settings pane appearances and both settings hosts.
It checks usable 430 × 560 settings content, native attachment and close/reopen, unchanged
selection/divider and a mounted but disabled background. It also checks that diagnostic Save/Cancel
retains its settings host while the native Save panel is nested under that sheet. Current settings/editor Light/Dark captures
must show the consistent desktop palette; the mini-panel retains its original styling.
`testDesktopSettingsBackdropCloseAndEscapePreserveEventsAndEditor`
separately exercises actual backdrop clicks, empty-area clicks inside the pane, the close button, Escape,
unchanged event data and the editor's retained outside-click protection. Current acceptance
must establish the shared attached native Settings sheet, with no independent settings window.
Use native close-button actions for in-process lifecycle checks; physical outside clicks and
Escape require the external/human interaction result rather than synthetic backdrop controls.
This is owner-to-rendered-UI evidence, not external popup-menu selection. Ordinary full panel
smoke remains the side-effect check for the shared settings change.

Divider-grip checks route real root-view hit testing through center/±5-point positions at several
heights and reject grip capture at ±8 points. They repeat after native divider/layout changes.
This establishes the transparent overlay's hit band and content pass-through, not real pointer
tracking. External acceptance must also drag from both sides of the line, far past both legal
width limits, then confirm ordinary content clicks and retained position.

The desktop route also exercises the explicit compact-mode footer and the real status-button
action: only the footer hides the desktop; toggling the status button leaves it visible.
Return through the panel footer preserves the hosting hierarchy, selected event, view and timer.
The compact-mode control is rejected while an editor owns the desktop or any desktop sheet is open or closing.
Status-button `performClick` is an in-process action, not proof of physical menu-bar input.
It additionally asserts unfinished-before-completed row geometry in both modes and after reopening
a task, without changing stored UUID order. Search-filtered creation checks Cancel,
query retention, durable Save, automatic search reset and shared panel visibility. Both modes
reject the obsolete favorite-only filter while retaining explicit favorite selection and its card.
Regression also requires accessory startup before desktop creation and regular activation after
desktop show, close, compact-mode dismissal and reopen. It rejects forced current/all-Space
desktop flags. These policy/flag assertions do not prove real Space switching or visual Dock
presence; exercise those externally under the user's existing Mission Control settings.

`./verify.sh desktop-capture <marked-output-directory>` runs those same scenarios and retains
the tested application, PNGs and manifest only after PASS. The destination must already contain
`.countdown-ui-capture-output`. Captures show native collection/feed and no-favorite states in
Dark/Light, a linked mini-panel after its rendered checklist reaches 2/2, plus shared weather OFF. The manifest records the exercised bundle version/build,
executable SHA-256, bitmap dimensions and synthetic-data scope. These captures identify the
exercised source build; they do not by themselves establish publication or a match to a released
package. The [1.15.0/30 release evidence](images/v1.15.0/PROVENANCE.md) separately identifies
the exact published candidate and its native captures.
Inspect the actual images before using them in README and preserve historical release captures.

For human acceptance, launch the retained test bundle with both `--visual-preview --desktop-preview`
and its marked `COUNTDOWN_MANAGER_TEST_HOME`. This preserves isolated events, preferences and
synthetic forecasts, while enabling normal production focus/lifecycle callbacks. `--desktop-preview`
without `--visual-preview` is rejected before Store startup. Never launch a test bundle without
its isolation environment and flags. Current release captures and acceptance protocols are recorded
in [the 1.15.0 provenance](images/v1.15.0/PROVENANCE.md). The earlier
[desktop development evidence](images/v1.14.1/desktop-unreleased/PROVENANCE.md), including external
keyboard observations and recordings, remains historical evidence with its original build limits.

Registered in-process controls, native field-editor calls and window APIs prove only the
corresponding state/layout boundaries, not physical command-bar clicks, external Command-N/Command-comma/
Command-W delivery, VoiceOver speech, perceived animation smoothness or status-item/Spaces behaviour.
Initial pane geometry at two sizes does not prove divider dragging at its extrema. Manually
exercise the divider in both directions, minimum window sizing, long titles/notes and independently
scrolling preparation. Verify real Dock activation/reopen, window close without quitting, application
switching with the desktop window left open and the panel still transient, and draft-preserving
close commands on a provenance-identified isolated bundle. Weather fixtures are not a live forecast,
provider-availability or native-location permission check. Record actual outcomes separately; the
presence of this route is not a completed acceptance result.

## Real UI Smoke

For empty-state changes, run full lint and `fast`, then `empty-state-capture` (which includes the
focused native scenarios). Deterministic Store checks distinguish loading/read failure/recovery
from a genuine empty list, and cover first Save, last-event expiry and midnight rejection. Native
checks exercise all three buttons with weekday titles and day/weather defaults, title updates after
date selection and preservation after a manual title edit, immediate Save without typing, no auto-save, Cancel, hidden repeated
actions, title focus, the actual NSDatePicker action, retained drafts through hide/show, return of
the nonempty header, ordinary plus/day defaults, and inline confirmed deletion. A synthetic clock
checks stale-today Save disablement, the current leaf after midnight and last-event expiry. Geometry
checks require no empty header/day row, centered content, 260 × 34 primary/32-point secondary actions,
and the unchanged timer/footer. Captures include Dark/Light, Light Increase Contrast, Dark Reduce
Motion, a running timer, today's native editor in both themes and synthetic midnight. The manifest
records bundle/executable provenance, appearance overrides and `emptyStateSyntheticDays`. These
in-process actions establish native state/layout, not external keyboard delivery or system Spaces.

`./verify.sh ui` builds a release application bundle from the current source tree in a temporary isolated environment. It exercises the real SwiftUI/AppKit hierarchy in process.

The harness launches that temporary bundle through macOS LaunchServices (`open -n -W`), with an
isolated test home passed only to that instance. It must run from a normal logged-in Aqua session:
the harness fails clearly when that session is unavailable rather than executing
`Contents/MacOS/CountdownManager` directly. Direct execution is not a valid AppKit launch path and
can abort during `NSApplication` registration before app code runs. Scenario success is read from
the isolated result file; the launcher itself is not the test result.

Current capabilities include:

- view construction and hosted root identity;
- panel/editor/list continuity across supported in-process hide/show paths;
- draft and scroll continuity;
- rendered control state;
- focus/responder paths reproducible in process;
- in-process AppKit mouse delivery and hit testing for the timer completion alert;
- main-thread stall detection.

`./verify.sh capture <marked-output-directory>` adds a separate isolated capture run. The output
directory must already contain `.countdown-ui-capture-output`; after a PASS it receives a timestamped
set of backing-scale PNGs and `manifest.json`. The captures cover an idle varied-height list, a
below-fold event promoted to primary, running and finished timer/list boundaries, the editor, the
empty state, Light appearance, Increase Contrast, and a running-timer render with Reduce Motion.
Two additional static endpoint captures record the timer preset pill at `120` and at `5` under
Reduce Motion. These stills prove final layout states, not movement over time; focused UIChecks and
Real UI Smoke cover the 180-millisecond motion policy, immediate reduced-motion policy, endpoint
selection, rapid last-tap-wins behaviour and the final value consumed by Play.
An isolated today-dated primary and short secondary event add a full-panel capture of the date and
`Сегодня` badge. The fixture is removed before the other capture scenarios run.
Three day-creation captures show the inline `Сегодня` / `Завтра` / `Выбрать дату` choices, the
default tomorrow `Новый день` editor and today's editor with the end-of-day expiry notice.
Real UI Smoke separately exercises the native date field for today and future dates, weekday title
updates and manual override, expiry notice visibility, Save/Cancel data boundaries and retained day
drafts through hide/show. Deterministic Store checks cover saving against a changed calendar day,
including rejection of stale drafts and prevention of expired-event recreation.
A fifteenth capture records a collapsed checklist under Reduce Motion. The capture scenario also
checks that hidden checklist controls reject input and that reopening restores the completion groups
without changing event JSON. The collapse regression exercises interrupted repeated requests, final
card height, independent disclosure preferences, hide/show continuity and reopening a completed task.
These checks establish final states and data boundaries; a still capture or motion-policy assertion
does not prove intermediate animation smoothness or exact wall-clock duration.
Appearance and accessibility values are injected only into the isolated retained hierarchy and are
recorded per image in the manifest; system settings are never changed. A still image under the
Reduce Motion environment proves that the state renders cleanly, while the deterministic animation
checks prove the selected animation type—it cannot visually prove motion over time.
They are evidence for the retained real panel hierarchy, not golden-image tests or proof of external
macOS interactions.

Limitations:

- it cannot prove that macOS delivered an external app switch, Space change, or status-item activation as a user would;
- its direct alert-window mouse events do not prove the first physical click while another app is active;
- test-mode lifecycle suppression or direct internal actions are not evidence of production system behaviour;
- configuration and property assertions support evidence but do not prove the corresponding user-visible interaction.

## Manual visual preview

`--visual-preview` opens the panel automatically for a manual visual QA session. It requires
`COUNTDOWN_MANAGER_TEST_HOME` and the `.countdown-visual-preview-environment` marker in that
separate directory. The mode isolates event data, timer preferences and diagnostics in that test
home, including the production-path overlap rejection used by the other runtime harnesses.

Unlike UI Smoke and XCUITest, visual preview preserves normal application deactivation, occlusion
and Space callbacks so that panel visibility behaves as it does in production. It is a manual
inspection surface, not automated verification evidence.

## Sparkle update verification

UIChecks covers configuration validation, native-continuation deferral and single consumption,
timer/editor/write blockers appearing after an update check, and final termination safety.
Controlled repository tests prove `Store.hasPendingPersistence` stays true until overlapping
success/failure and recovery operations finish. Real UI Smoke additionally opens an actual editor,
retains draft text through hide/show, blocks the update continuation with that editor and a running
timer, and resumes only once after Cancel and timer deletion. These checks use a disabled updater;
they prove application guards, not archive download/replacement or native Sparkle UI.
The public modal/session delegate callbacks additionally exercise retained-panel hiding, ordinary
level on explicit reopen, unchanged editor hierarchy/draft and timer deadline, delayed level
restoration, and no implicit reopen. Calling these callbacks in process proves the shell response;
actual Sparkle delivery and window accessibility require the signed-feed acceptance below.

`python3 -B scripts/prepare_update_test.py --output /private/tmp/<fresh-directory>` builds two
separate ad-hoc bundles with increasing build numbers, a disposable file-based Ed25519 key,
a signed ZIP/appcast, and local feed/launch scripts. Preparation alone is not an update PASS.
Both bundle plists embed a marked isolated home and the dedicated update-test bundle identifier;
the relaunched process requires the same isolation even when LaunchServices drops env/argv.
Missing/invalid test isolation exits before production Store, timer or diagnostics can start.
Production configuration refuses HTTP; explicit test bundles allow only `127.0.0.1` HTTP.

For actual acceptance, launch the older fixture and use ordinary Sparkle UI to find/download/install
the newer archive. Open an editor and start a timer after the check begins; confirm installation
waits and draft text remains. Cancel/Save and end the running timer, explicitly install, then verify
the running process path, new CFBundleVersion, preserved fixture JSON, timer/disclosure preferences,
and logs in the isolated home. Also test rejection of a damaged archive/signature and offline
manual checks. Verify nested code signatures, symlinks and executable modes after ZIP extraction.
Record exact bundle/feed provenance and distinguish completed update from a prepared fixture.

For updater window ordering, begin with the host panel open and invoke the settings or application-menu
check. Observe accessible checking and found-update controls with the panel hidden. Explicitly reopen
the panel during downloading, then verify Ready to Install remains accessible. Exercise manual
refocus, scheduled-found presentation, no-update and offline-error alerts. With a retained editor or
running timer, press Install, use `Вернуться к работе`, confirm draft/deadline continuity, then retry
from the ready-update settings action after Save/Cancel and timer completion/deletion. No dismissal or return
to work may loop into installation. Keep external clicks and production callbacks enabled in these
isolated update-test bundles; internal delegate calls alone cannot close this acceptance gap.

The test does not certify a public HTTPS deployment, Gatekeeper first-install behavior, Intel,
or every supported macOS release. These require their own evidence when released or changed.

## Settings and keep-awake verification

Run full SwiftLint and `./verify.sh fast` before product QA. Focused deterministic checks must
exercise the keep-awake owner through a fake create/release boundary: initially disabled state,
successful enable/disable, repeated requests without duplicate assertions, create and release
failures with unchanged accepted state, retry, termination cleanup, fresh-owner restoration of saved
ON, and persisted explicit OFF. A restore failure retains intent while reporting inactive/error.
These checks must not hold real IOPM assertions or change global power settings. Include settings
navigation and confirm that settings alone never becomes an updater editor blocker.

After those checks are green, use isolated Real UI Smoke and current-source panel captures for
the changed SwiftUI surface. Check the following observable contracts:

- one retained 390 × 600 panel with the timer above both list and settings;
- one-row storage/gear/Quit footer, a 14-point gear before Quit, and unchanged calendar/`+` header controls;
- three compact settings groups: `Приложение`, `Погода`, `Обслуживание`, with native checkbox/menu
  controls, the existing manual-update action and `Сохранить диагностику…`, without navigation arrows;
- Back returns to the same list scroll position; hide/show retains settings navigation;
- settings entry cannot replace an open editor or lose a draft, and hidden screens reject input
  and are absent from interactive accessibility content;
- immediate checkbox changes without Save/Cancel, visible errors, disabled unconfigured-update
  controls, and the login `requiresApproval` affordance without mutating production login registration;
- ready/deferred installation replaces manual check and retains explicit retry and current
  timer/editor/persistence restart guards;
- keep-awake checkbox/accent and the gear state dot agree with the accepted owner state; Back,
  hide/show and timer actions leave that state unchanged.

Capture settings off/on, the compact list footer, and relevant Light/Dark and Increase Contrast
states. Record actual bundle provenance and capture overrides. A capture demonstrates layout;
fake-adapter tests and UI state do not establish macOS power assertion delivery or actual idle
sleep behaviour.

For a bounded native acceptance check, enable keep-awake only in an isolated current-source app
and inspect the assertion attributed to that process with `pmset -g assertions`. Confirm one
`PreventUserIdleDisplaySleep` assertion, repeated enable without duplicates, retention through
panel hide/show and timer changes, removal on disable and termination, restored ON after a new
launch with saved ON, and persisted OFF after explicit disable. Always turn the mode off or
terminate that isolated process in cleanup; do not
leave sleep-prevention assertions running after QA. Use no system-wide power-setting changes.

Seeing the process assertion proves native registration, not a complete real-idle experiment.
If actual idle display/system sleep is not observed over the configured idle interval, report
that remaining limit explicitly. Screen saver, security lock, lid close, manual sleep and
low-battery sleep are outside this feature's prevention contract. Normal app-switch and Space
continuity still require the existing manual macOS acceptance where the driver cannot reproduce
them faithfully.

## Compact interface and diagnostic export verification

After full SwiftLint and `./verify.sh fast` are green, exercise the redesigned hierarchy through
isolated Real UI Smoke and capture the actual 390 × 600 panel in Light/Dark and Increase Contrast.
Compare against the approved list/editor/settings composition, including the later independent
icon-field correction. Use one initial batched visual inspection and at most one correction batch;
keep all fixture forecasts and event dates identified as synthetic.

Check the compact featured and secondary title/calendar bounds, separate star/edit hit areas,
Russian event count, full-width checklist disclosure with left chevron/right progress, empty-state
create action, native fields and the unchanged retained list/scroll hierarchy. Verify that an empty
note is immediately editable through `editor.note`, with the ordinary placeholder and live
`editor.note.count` starting at `0/150`. Empty and filled notes survive panel hide/show; Cancel
does not restore the discarded text in a new draft, and clearing with Save persists an empty note
that remains visible on reopening. Keep the outlined
icon field distinct from the checkbox group with its 13-point separation, and exercise the existing
eight presets, five 6 × 8 catalog pages, selection/clear, focus and Reduce Motion behavior. Confirm
Delete/Cancel/Save remain in the fixed footer and deletion still requires inline confirmation.
Today's ochre warning must preserve the exact expiry text and current-day validation semantics.
Native rounded-border title, note and subtask fields must show one native frame when unfocused
and only the native focus treatment when focused, in both Light and Dark appearances. Captures
17/21 retain subtask focus, 18/22 title focus and 19/23 note focus; the other native fields remain
unfocused in each image. Inspect all six current images manually for duplicate borders/focus
outlines, while preserving the independent outlined emoji selector. The native first-responder
checks establish focus identity; fast PASS and geometry checks do not replace this visual acceptance.
Capture04 deliberately shows an existing editor with text focus cleared; its log records
`text_focus=none`. It covers the existing-event form and Delete footer. The six focused-field
captures remain mandatory. A cache-rendered initial focus halo is not evidence of a settled
focus appearance or proof of how the transition draws on screen.
Geometry/state assertions demonstrate settled layout and controls, not perceived animation quality
or physical external clicks.

`DiagnosticExportChecks.swift` covers the archive boundary using isolated logs, destinations and
injected failures. Verify known-only redaction with hostile legacy text/URLs/paths/user content,
current/previous rotation generations, bounded reads and ZIP contents, technical summary fields,
missing/empty logs, cancellation and write/archive failures. A failed or cancelled export must clean
its temporary files and preserve an existing destination. Confirm MainActor progress while a slow
writer/export runs, bounded message admission (512 pending records, 4 KiB input budget), and pressure
drops without blocking the caller. These checks must never read production logs or event files.

Native save-dialog acceptance is separate: from an isolated current-source app, press
`Сохранить диагностику…`, inspect the `NSSavePanel` filename/type and normal save/cancel routes,
choose a temporary destination, then inspect the completed ZIP and visible failure recovery.
Confirm the panel/editor/timer session survives this dialog and no upload occurs. A direct exporter
call does not certify `NSSavePanel`, Finder delivery, user-selected file access or production shell
ordering. Record this native path as unverified until it has actually been exercised.

The general Real UI Smoke scenario currently verifies native open → Cancel → reopen → Cancel,
sheet detachment, released exporting state, unchanged event JSON and absence of output archives.
It deliberately does not call `NSSavePanel.ok(nil)`. An isolated AppKit probe completed Cancel and
immediate reopening but hung on that programmatic Save call; this is a driver limitation, not proof
that the physical Save control fails. Fast checks exercise the ZIP worker, redaction and archive
failure/cancellation paths independently. The earlier XCUITest attempt timed out entering
automation mode and supplied no successful Save interaction evidence. The focused 2026-10-24
1.15.0/30 preflight subsequently passed native Cancel → reopen → typed destination → actual Save
with the user's ABC input source. Its [protocol](images/v1.15.0/preflight-input-diagnostics.json)
records independent ZIP inspection, unchanged event bytes and no clipboard fallback. This is
external evidence for that identified build and input source; general in-process smoke still
proves only its Cancel routes, and other input layouts remain outside that acceptance.
The 1.18.0 release additionally passed the actual diagnostic Cancel/Save/ZIP-inspection route
under ABC after correcting native Go to Folder text clearing in its test driver. Its
[external receipt](images/v1.18.0/external-xcui.json) records the full 27/28 run and affected-only
1/1 repeat separately; this does not expand the in-process Save driver's capabilities.

## Weather verification

For diagnostic-only weather changes, run full SwiftLint and `./verify.sh fast`, with focused
deterministic transport/controller checks using synthetic responses, isolated preferences and an
injected diagnostic sink. Check paired request UUIDs, fixed service/result categories, success and
empty/invalid payloads, HTTP status, numeric URL errors, cancellation, elapsed duration and decoded
versus full-day/temperature/condition/usable counts. A response that starts with HTTP 200 and
partial bytes but ends in a URLSession timeout must remain a failure with unknown complete
response status/size. Exercise availability/suppression changes and repeated unchanged refreshes
to verify bounded transition records. Use private sentinel URLs, coordinates, city names, event content and response bodies in
fixtures and assert they do not reach diagnostics; localized/arbitrary error text must not be
recorded. Exercise one failing source alongside a successful one and a partial-day result that
does not create a badge. Confirm that adding diagnostics preserves the existing
request/retry/cache/cancellation behaviour. The injected sink checks emitted records, without
claiming a physical journal write or rotation test. These checks do not establish live service
availability, native location delivery or
the reported failure on another Mac. No application UI or screenshot run is needed when UI,
network behaviour and data contracts are unchanged. Preparing a release still requires fresh
README screenshots under that version and provenance verification according to `AGENTS.md`;
that release requirement is separate from diagnostic-only regression evidence.

Snapshot checks must cover launch with restored weather preferences/demand, automatic settling
of ordinary work, and an explicit `.diagnostics` snapshot of unchanged state. Confirm bounded
automatic repeats, the fixed launch/diagnostics/settled reasons and private-field exclusions.
Compare provider/location/scheduler call counts before and after explicit snapshots: observing
state must not trigger a refresh, retry, permission prompt or native request. The Settings action
must enqueue its weather snapshot before the explicit native export dialog; after a confirmed
destination, the asynchronous journal snapshot must be ordered after already-admitted records.
No production UI path may synchronously drain the writer. Deterministic snapshot/export tests do
not by themselves establish native save-dialog delivery, a real post-update relaunch or journal
durability on a different Mac.

Run full SwiftLint and `./verify.sh fast` before product QA. Existing flag/draft tests retain legacy
JSON false, Save/Cancel and no title migration. New deterministic normalization checks cover all
three services, median 1/2/3, categorical majority/wet ties, distinct source votes, invalid units and
missing values, exact intervals and DST. MET tests cover non-overlapping 1/6/12-hour periods, interval
maxima, dense Celsius hourly fallback versus sparse/incomplete/invalid grids, and frozen-thunder
symbol aliases. Wttr tests require exactly eight unique accumulated 3-hour amounts, never *3, and
suppress mixed/frozen/unknown liquid totals. Open-Meteo checks explicit timezone/date bounds and
actual fixed 24-hour periods; no clipping of sums or maxima.

Controller fake-clock/scheduler/source tests cover one parallel request per source/range, progressive
1/2/3 results, duplicate event demand, independent failures/Expires/429 Retry-After/304 Last-Modified,
fresh sources during another request, autonomous expiry, bounded contexts and OFF/location/shutdown
late callback rejection. Only full-day consensus reaches the compact badge; partial records do not
pretend to be daily maxima. All tests use isolated preferences and no real forecast/location requests.

Resilience coverage uses separate wall/monotonic clocks, fixed jitter, source-continuation barriers,
and snapshot/log barriers with failure deadlines (not sleeps/yield counts as sequencing). It checks
the exact 10/45/300/900/1800-second cold-timeout sequence at zero jitter and upper jitter bounds;
permanent invalid-response has no retry at +301 and exactly one at +1801; a 20-second TTL disappears
at +20 but cannot refetch before +60; the seventh city request waits for the 600-second budget slot.
Typed HTTP fixtures cover max-age/Date/Age/duration, invalid/conflicting/missing headers, signed
diagnostic intervals, no-cache/no-store/must-revalidate, all receiver HTTP-date forms and malformed
or far-future Retry-After. Actual injected URLProtocol transport tests inspect conditional headers
and ensure 304 carries metadata instead of decoding an empty body. Controller cases validate weak
ETag/partial304 merges, no heuristic TTL reset, orphan/mismatched304 and bounded unconditional GET.

Network fakes cover unknown/offline, debounced recovery, a satisfied path followed by timeout,
expensive/constrained/Low Power, and stale monitor callbacks. Provider-wide 429/503 gates survive
OFF/ON/city changes and wall-clock rollback; an observed late429 still constrains later starts.
Clock barriers cover doubtful freshness withdrawal, a queued pre-jump response, coalesced wake
refresh and a new midnight range without old validators. Wall-only rollback preserves ordinary
404 and slow temporary500 deadlines for cold failures and retained full/partial bodies; no GET
starts before the original monotonic deadline. Previously fresh success keeps its bounded recheck.
A synthetic MET alreadyExpired200 plus
two timeout sequence checks independent recovery and early useful publication. It models allowed
code paths; it does not establish the original incident's unknown headers. Held source/compute
continuations allow a MainActor progress marker before release. The prior diagnostic settlement
race waits for actual request/computation completion; it does not equate badge publication to group
completion. Existing cancellation/demand/location/DST tests remain in the same fast gate.

No disk relaunch/persistence claim is made. Real NWPathMonitor delivery, sleep/wake, VPN/TCC/AUTO,
Low Power transitions and public-service availability require separately recorded real evidence.
After final lint/fast, run focused weather native smoke and the empty-state integration smoke. If a
native city-menu driver is unsupported on the host, record its exact failing boundary separately;
do not weaken its assertion, claim that synthetic setup proves selection, or repeat it indefinitely.
The 2026-10-19 host hit this limitation after two scenarios: pre-tracking SwiftUI city-menu
inspection returned an empty item array with an AppKitPopUpAdaptor coordinator. That run is
recorded as a driver failure, not a weather publication PASS. Snapshot reads also check clock
consistency before refresh, so diagnostic availability cannot contradict the guarded getter.
Deletion cases cover two distinct days and two events sharing one date: deleting one retains useful
requests, deleting the last cancels all three children and leaves no scheduler; late replies cannot
repopulate the cache. Paused, deliberately noncooperating computations test subset-deletion and newer
provider outcomes against the separate computation revision. Decoder/consensus cancellation wins
before malformed-data handling. JSON decoding itself is not preemptible inside Foundation's call.
Keep-awake tests use fake adapters and isolated suites, including fresh defaults objects across
simulated bundle replacement, restoration/retry failures, failed release and termination. Weather
enablement/city also survive a new controller/defaults object; no standard preferences are fixtures.
Version formatting reads distinct temporary Bundle Info dictionaries instead of hardcoded releases.
The focused native fixture injects a failing keep-awake adapter: Settings shows inactive state,
checkbox retry preserves saved ON after failure, and `Не включать при запуске` clears intent/error
and removes itself. No native assertion is created in that recovery scenario.

Header formatter checks exercise Russian event-count endings (`1 событие`, `2 события`,
`6 событий`, including teen and compound-number cases), weekday/month/year boundaries and no-year
date formatting. A controlled Store clock tests midnight publication.
The focused native runtime observes `header.today` and the count with one event, then their absence
and the updated `event.empty.date` after expiry across an injected midnight, without exposing
Store.today, adding a view timer or changing the system clock.

`./verify.sh weather` builds an isolated current-source app and runs only focused weather/header
scenarios. Native NSPopUpButton enabled OFF/ON and its Auto/ten-city menu are inspected; the public
NSMenu item action selects Moscow and updates its binding. Real view frames verify the featured badge beside its countdown, ordinary badge in the date/remaining
metadata row, and a system-15-semibold header date above the compact event-count line at width 390.
Editor defaults, hide/show, durable Save/Cancel, OFF, false per-event flag and missing forecasts are
checked. Weather has no links/tooltips/privacy/licence/info/loading/error text in app UI. These
in-process actions do not claim physical popup clicks, external keyboard or real CoreLocation.

`./verify.sh weather-capture <marked-output-directory>` uses the same focused scenarios without
rerunning the general smoke/continuity suite. The destination must contain `.countdown-ui-capture-output`.
After PASS it copies ten PNGs plus a version-5 manifest: weather list Dark/Light/Light Increase Contrast,
OFF Dark, settings Dark/Light, editor Dark/Light, and `weather-header-before-midnight` /
`weather-header-midnight-empty`. The ordinary capture set remains 31 images. The manifest records
exercised bundle version/build, executable SHA256, injected header dates and synthetic forecast source,
alongside appearance/geometry/color-profile fields. Every isolated app mode uses synthetic +14°C
forecasts with day +2 deliberately absent, and disables native location and forecast HTTP.

Live acceptance is a separate authorized command using the actual three WeatherTransport clients,
a public named city and isolated synthetic event demand. Record each service HTTP/decoder result and
available numeric/category dates; a stored fixture or browser-side probe is not a live client PASS.
Do not claim the reported second Mac's failure is reproduced if that Mac was not accessed. Manual
city/global ON/per-event ON/date/cache gates are inspected independently of native geolocation.

Capture weather present and absent in the related Light/Dark and Increase Contrast states,
including settings and the editor choice. Record actual source/bundle provenance and label
injected forecasts as fixtures. These images prove native layout with demonstration data, not
current weather, real location permission or provider coverage.

For a real-service acceptance, use an explicitly authorized isolated bundle with native location
requests enabled. Observe the normal macOS permission flow for Automatic and separately denied
permission/manual fallback; confirm that restored enabled state does not prompt for undetermined
permission. Then check one ordinary asynchronous forecast request, missing days,
offline handling and global disable during an outstanding request. Do not enable real permission
requests in development or routine smoke/capture modes. If this acceptance has not run, report
the exact unverified native-location/network path; fake callbacks and sample JSON are not proof
of native permission delivery or live service availability. Device coordinates must not appear
in logs, saved preferences or event fixtures.

Validate the request/decode contract against [official Open-Meteo API documentation](https://open-meteo.com/en/docs)
and keep data attribution aligned with its [licence](https://open-meteo.com/en/licence) and
[service/privacy terms](https://open-meteo.com/en/terms). A successful public-coordinate HTTP probe
supports endpoint/schema compatibility only; it does not prove native permissions, application
integration or all city/date coverage.

## XCUITest

### Input-source ownership during external checks

When system file-picker path entry or Cyrillic/Latin typing needs a particular enabled input
source, the agent selects it through normal macOS input-source controls rather than asking the
user to switch it. Record the original active source, verify the selected source with a read-only
TIS query, run the ordinary keyboard interaction, and restore/verify the original source when
finished (also after a failed check). Do not add/remove configured input sources or change their
preferences. If the required source is unavailable, report that concrete limitation.

The 1.18.0 preflight selected existing ABC through system keyboard shortcuts and restored Russian.
System Go to Folder uses actual current-layout Command-A, Delete, an empty-field assertion,
ordinary typed input and exact path equality before Return. Unicode text entry retains its
separate exact-value assertions. A transient system InputSource HUD is observed with a bounded
read-only wait; no blind Escape, clipboard substitution, repeated typing or skipped validation
can turn an input failure into a pass. Successful ABC delivery does not certify every IME/layout.
[Release evidence](images/v1.18.0/PROVENANCE.md) separates the initial failures, full 27/28 repeat
and affected-only 1/1 diagnostic repeat.

### Historical external evidence

The 2026-10-23 [regression campaign](qa/desktop-regression-2026-10-23.md) records 20 successful
unique external scenarios out of 22 across separately identified runs, not one all-green suite.
The Latin-input and complete native diagnostics-Save routes were unaccepted in that historical run;
the source tests were retained rather than skipped. On 2026-10-24 both passed in a focused 1.15.0/30
preflight with the user's ABC source confirmed: original Latin note limit/focus/Undo, native
Cancel/reopen, ordinary typed destination path, actual Save and ZIP privacy/data checks. Native
Save/Go to Folder controls use their observed identifiers; command characters follow the current
input layout. No clipboard fallback, skipped validation or global input-source change is used.
Earlier failures reproduced Latin loss in Apple's system PathTextField under Russian input, so
the successful ABC run is not proof that XCTest supports every layout. This closes those two
specific gaps, not every manual-only scenario in the broad campaign. Popup city interaction is covered by
`testWeatherCityMenuSupportsNativeSelection`: actual menu opening, all eleven choices, Moscow
selection and OFF/ON retention. In-process weather smoke separately changes the shared owner
and checks native rendering; it does not introspect an unopened dynamic SwiftUI menu.

`./run-xcui-tests.sh` builds with temporary DerivedData and isolated test data.
The Xcode target includes `StatusBarImages.swift` and its three menu PDF resources, matching
the runtime loader used by the Swift package build.

The focused editor cases `testNewEventTypingAfterFocusedSubtaskDeletionCancelAndSave` and
`testExistingEventTypingAfterFocusedRowDeletionSurvivesSaveAndReopen` use normal delete buttons
and subsequent `app.typeText` input in explicitly selected neighbor/title/note fields. They inspect
durable JSON and the reopened editor, including preserved completion/favorite and a clean new
draft after Cancel. Their external delivery result must be recorded separately from native smoke.
On 2026-10-22 both focused cases passed on the logged-in Apple Silicon host: two tests, zero
failures. The same source passed strict SwiftLint, `verify.sh full` including all four native
new/existing × Save/Cancel editor paths and Thursday/Friday date actions, and 32 deterministic
eval-runner checks. This does not establish external date-picker interaction, IME input or Spaces.

Current reliable capabilities include keyboard entry, normal application buttons, and Command-W after the application is active.

Focused subtask-row XCUITests click the known checkbox element at its checkbox, label and trailing
empty regions, then check durable completion/reopening and unchanged sibling state. Disclosure
collapse/reopen must leave event JSON unchanged. The existing subtask editor case protects normal
text entry/Save/Cancel. The optional note field is directly visible and editable for both empty and
filled drafts. Keyboard activation retains the native checkbox control. A Space request
immediately after a mouse toggle/reorder does not establish keyboard focus: that diagnostic failed
on both the baseline and changed implementation and is not an acceptance test. Verify Space only
after the checkbox has actually received keyboard focus through normal keyboard navigation.
These within-control coordinates do not establish status-item, app-switch or Spaces interaction.

Do not treat Finder anchoring, coordinate clicks, repeated timing loops, or custom driver machinery as reliable proof of status-item activation, application switching, or Spaces lifecycle. Those approaches can change the lifecycle under test and remain diagnostic only.

## Manual-only macOS acceptance

The current automation cannot faithfully reproduce these system interactions. Verify only the scenarios relevant to the changed contract:

1. A fresh-launch status-item click opens an arrowless panel directly below the status item.
2. Hiding and reopening preserves the same in-memory session when required by the product contract.
3. Rapid repeated status-item clicks produce one immediate visibility toggle per distinct click.
4. Switching to another application hides the panel.
5. Switching Spaces hides the old panel without losing the editor or draft; returning does not reopen it, including after a rapid return.
6. Clicking the status item from another Space keeps that Space active and opens below its status item.
7. The panel has no arrow, title bar, or traffic-light controls and cannot be dragged as a standalone window.

If a future driver can reproduce one of these interactions without altering it, replace that manual limitation with reliable automation.

## Isolation and provenance

Never mutate production Countdown Manager data during tests.

Real UI Smoke and XCUITest require explicit isolated data, defaults, and log locations. If safe isolation cannot be established, do not run the mutating verification path.

Runtime evidence applies only to the bundle that was built and exercised. `./verify.sh ui` builds from the current source tree; `./run-xcui-tests.sh` builds through the current Xcode project. An old `.app` is not evidence for current source unless its provenance is known.

Optional-icon/favorite coverage includes a sixteenth capture, `16-nearest-today-without-icon`: the historical filename is retained, but the Today event has no additional emoji or explicit favorite and uses an ordinary compact card, no featured heading and an unfilled star. Real UI Smoke exercises empty-icon Save, draft-only clear/Cancel, menu fallback, explicit favorite select/clear in the list and editor, and a fresh repository read preserving absent selection. External XCUITest adds ordinary button and keyboard cases for these flows; it retains the existing lifecycle limitations.

Editor/emoji coverage retains captures 17–24: empty and selected emoji fields, compact presets and the
full catalog in both Dark and Light appearances. Real UI
Smoke exercises the selector's closed/presets/catalog states, all eight columns across the five
catalog pages, selection and clear actions, repeated disclosure requests, isolated live Reduce
Motion, draft preservation and retained hide/show behavior. External XCUITest covers normal selector,
preset, catalog and clear-button interaction. Captures prove settled layouts; they do not prove
perceived animation smoothness or precise wall-clock duration.

Captures 25–28 record the actual timer completion alert window in Dark and Light appearances,
including both Increase Contrast variants. With the today editor and Settings captures, the full set requires 31 images. The manifest records
the source window and appearance for each capture. Appearance is overridden only on isolated test
windows; global macOS display settings are unchanged. Real UI Smoke checks shared palette colors,
appearance changes on the reused alert, title/background click dismissal, unchanged finished timer
state and app focus, and the five-second automatic dismissal. In-process mouse delivery remains
distinct from a physical first click while another application is active.

Captures 30–31 record the internal Settings screen in Dark and Light appearances through the
ordinary `settings.open` and `settings.back` controls. Both require Keep awake to remain OFF;
capture mode does not acquire a sleep-prevention assertion. Returning preserves the list hierarchy
and scroll position. These images show native settled layout, not actual prevention of idle sleep.
Settings captures retain the full-panel opacity checks and the existing top/middle content checks.
The bottom bitmap band may be blank by design; visible content is additionally checked in the actual
registered Back, Keep awake and update-action frames. Other capture layouts retain every existing
band check. Rejected raw bitmaps are saved separately under the isolated home's `FailedCaptures`;
they are diagnostic evidence only, and the ordinary verification wrapper still cleans its temporary home.

Completion-icon motion checks exercise the native image layer's animation key, fresh cycle timing,
live Reduce Motion, hidden/dismissing-state suppression, interrupted dismissal/re-presentation,
identity resets and unchanged label/card geometry. UIChecks cover bounded transform keyframes,
coordinate direction and the burst/pause policy. Popup stills 25–28 explicitly use isolated Reduce
Motion and record that override; they show resting layout, not perceived animation smoothness.

Editor Add/Delete motion coverage exercises 0/1/10 limits, animated removal and disabled outgoing
controls, stable neighboring UUIDs/text/completion, focus and scrolling, live Reduce Motion and
Save/Cancel boundaries. A focused external XCUITest types into newly added rows, deletes a middle
row and verifies the retained neighbors after Save. Settled geometry and motion-policy checks do
not establish perceived intermediate smoothness.


### Panel pending-show acknowledgement regression

`PanelPresentationChecks.swift` covers pending-show/visible acknowledgement, late hidden/visible
observations, reset on explicit hide and 200 rapid request sequences. These are pure request-state
checks, not physical Space acceptance. The existing full desktop status-hide→compact flow retains
its strict visible-panel assertion without adding a settlement wait. A real failure at scenario 10
was traced to an occlusion callback hiding a newly requested panel before its visible acknowledgement;
that run must not be labelled a false positive or combined with a subsequent passing campaign.


### Desktop sheet update restart

The desktop native route now includes31 scenarios. It checks actual read-only Settings/library/preview
sheet termination policy, and retains protection on event editors before and after Settings.
Standalone real SwiftUI-sheet Apple-event controls reproduce default native blocking before the
application delegate. The2026-10-29 correction also passed a genuine isolated Sparkle update with
desktop Settings attached: fixed-source build20120→20121 automatically relaunched without manual
sheet closure or app reopening, preserving JSON, copied bytes and selected preferences.
[Protocol and failed/successful evidence](qa/desktop-update-restart-2026-10-29.md).
The initial native focus loss on a Space change is recorded separately from final31/31.
