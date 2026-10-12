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
| Combined | `./verify.sh full` | `fast`, then Real UI Smoke |
| XCUITest | `./run-xcui-tests.sh` | External keyboard and normal button interaction through Xcode |
| Hook regression checks | `python3 -B Tests/test_swift_harness.py` | Deterministic Python hook checks; no application data or Swift builds |
| Eval runner checks | `python3 -B Tests/test_agent_evals.py` | Deterministic checks of fixtures, grading and execution; no model calls |
| Native transport checks | `python3 -B Tests/test_native_hooks.py` | Local protocol/cleanup regression checks; no Codex process or model calls |
| Update packaging checks | `python3 -B Tests/test_update_tools.py` | Feed/key/output/isolation boundaries; no production keys, application data or publication |
| Agent behaviour evals | `python3 -B evals/run.py run --model <supported-cli-model> --output evals/artifacts/<new-run>` | Opt-in isolated Codex runs plus independent checks and rubric review |
| Native Codex hooks | `python3 -B evals/native_hooks.py --model <supported-cli-model> --output evals/artifacts/<new-native-run>` | Opt-in real app-server delivery, trusted hooks, lint/fast failures and automatic repair; CLI 0.157.1 |

SwiftLint must be available on `PATH`; on macOS install it with `brew install swiftlint`.

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
- repository behaviour and persistence revision handling.

It does not prove SwiftUI rendering, AppKit lifecycle, focus, accessibility interaction, or window behaviour.

## UIChecks

`UIChecks` covers deterministic presentation and application-state behaviour:

- menu-bar and human-readable date formatting;
- editor validity, drafts, grouping, and disclosure state;
- presentation state transitions;
- persistence coordination visible to the UI layer.

It does not prove real AppKit event routing, external keyboard delivery, system focus, application switching, or Spaces behaviour.

## Real UI Smoke

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

For updater window ordering, begin with the host panel open and invoke the footer or application-menu
check. Observe accessible checking and found-update controls with the panel hidden. Explicitly reopen
the panel during downloading, then verify Ready to Install remains accessible. Exercise manual
refocus, scheduled-found presentation, no-update and offline-error alerts. With a retained editor or
running timer, press Install, use `Вернуться к работе`, confirm draft/deadline continuity, then retry
from the ready-update footer after Save/Cancel and timer completion/deletion. No dismissal or return
to work may loop into installation. Keep external clicks and production callbacks enabled in these
isolated update-test bundles; internal delegate calls alone cannot close this acceptance gap.

The test does not certify a public HTTPS deployment, Gatekeeper first-install behavior, Intel,
or every supported macOS release. These require their own evidence when released or changed.

## XCUITest

`./run-xcui-tests.sh` builds with temporary DerivedData and isolated test data.

Current reliable capabilities include keyboard entry, normal application buttons, and Command-W after the application is active.

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

Grouped-editor coverage adds captures 17–24: empty and selected emoji fields, compact presets and the
full catalog in both Dark and Light appearances. Real UI
Smoke exercises the selector's closed/presets/catalog states, all eight columns across the five
catalog pages, selection and clear actions, repeated disclosure requests, isolated live Reduce
Motion, draft preservation and retained hide/show behavior. External XCUITest covers normal selector,
preset, catalog and clear-button interaction. Captures prove settled layouts; they do not prove
perceived animation smoothness or precise wall-clock duration.

Captures 25–28 record the actual timer completion alert window in Dark and Light appearances,
including both Increase Contrast variants. With the today editor capture, the full set requires 29 images. The manifest records
the source window and appearance for each capture. Appearance is overridden only on isolated test
windows; global macOS display settings are unchanged. Real UI Smoke checks shared palette colors,
appearance changes on the reused alert, title/background click dismissal, unchanged finished timer
state and app focus, and the five-second automatic dismissal. In-process mouse delivery remains
distinct from a physical first click while another application is active.

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
