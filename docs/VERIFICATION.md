# Countdown Manager — Verification Surfaces

This file is the project-specific map of available verification commands, what they can prove, and where they stop. Product acceptance methodology lives in `.agents/skills/product-qa/SKILL.md`.

Product behaviour is defined by `docs/PRODUCT.md`. Tests are evidence for that contract, not a replacement for it.

## Commands

| Surface | Command | Cost and scope |
| --- | --- | --- |
| SwiftLint | `swiftlint lint --config .swiftlint.yml --strict --no-cache` | Fast static checks over `Sources`, `Tests`, and `XCUITests` |
| CoreChecks + UIChecks | `./verify.sh fast` | Fast deterministic regression gate |
| Real UI Smoke | `./verify.sh ui` | Release build plus isolated in-process SwiftUI/AppKit runtime scenarios |
| Real panel captures | `./verify.sh capture <marked-output-directory>` | Opt-in isolated PNG evidence copied only after the capture runtime passes |
| Weather Real UI Smoke | `./verify.sh weather` | Focused isolated weather controls, native city menu, badges and editor persistence |
| Weather panel captures | `./verify.sh weather-capture <marked-output-directory>` | The focused weather/header scenarios plus ten synthetic PNGs; no general UI rerun |
| Empty-state Real UI Smoke | `./verify.sh empty-state` | Focused day creation dates/weekday defaults, Save/Cancel, retained drafts, deletion/expiry and midnight |
| Empty-state panel captures | `./verify.sh empty-state-capture <marked-output-directory>` | Same focused scenarios plus eight isolated empty/editor captures; no weather HTTP, update or general UI suite |
| Compact cards/notes | `./verify.sh compact-capture <marked-output-directory>` | Focused native note editing, 51pt cards, featured date/weather and 26 isolated PNGs |
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
baseline or treating the failure as success. A successful gate is cached against Swift contents plus
`.swiftlint.yml` and `verify.sh`; changing those verification inputs invalidates the cached result.
This cache does not track every toolchain or environment change; rerun affected checks when those
change materially. Hook regression checks cover state failures, Stop gates, cache invalidation,
read-only calls and concurrent lifecycle calls. They do not prove native hook registration or trust.

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
a saved event crossing civil midnights/year boundaries and leap-day Tomorrow. The status-bar
formatter remains numeric. These text/layout checks do not require repeating external note entry.
The focused XCUITest `testNewNoteHardLimitAndNativeFocus` exercises actual keyboard 149→150→151
rejection, title/note handoff and Undo in a NEW note. Internal native calls do not prove physical IME keyboard delivery,
VoiceOver announcements, or external keyboard routing; record those separately when exercised.
The 2026-10-20 host returned `hasMarkedText=false` and a zero-length markedRange at UTF16-end
after accepted IME commit, both in NoteTextView and in an unmodified NSTextView baseline. This
differs from Apple's documented NSNotFound sentinel. Acceptance requires exact native/draft/expected
text equality, 150 graphemes, the correct caret, no active marked text, and the same empty range as
the native baseline; it does not rewrite product composition state to satisfy a sentinel assumption.
Role-specific geometry markers avoid stale shared-calendar frames after featured/secondary changes.

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
failure/cancellation paths independently. Physical Save is still unconfirmed: the attempted
XCUITest acceptance timed out entering automation mode, so the added external Save case supplies
no successful interaction evidence. Preserve this distinction until a real native Save succeeds.

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

`./run-xcui-tests.sh` builds with temporary DerivedData and isolated test data.

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

Optional-icon/favorite coverage includes a sixteenth capture, `16-nearest-today-without-icon`: the Today event has no additional emoji and no explicit favorite, with the nearest-event heading and unfilled star. Real UI Smoke exercises empty-icon Save, draft-only clear/Cancel, menu fallback, explicit favorite select/clear in the list and editor, and a fresh repository read preserving absent selection. External XCUITest adds ordinary button and keyboard cases for these flows; it retains the existing lifecycle limitations.

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
