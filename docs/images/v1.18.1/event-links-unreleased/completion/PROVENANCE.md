# Event links — feature complete, 2026-10-27

Status: accepted in the working version, not published or installed over the production app.
Version metadata remains 1.18.1 / build 34 while the next release scope is being assembled.
This record supersedes the earlier unresolved desktop status; earlier failures remain historical
evidence in the parent/disclosure directories.

## Final verification

- Strict SwiftLint: **0 violations, 79 files**.
- CoreChecks and UIChecks: **PASS**. Includes model/JSON compatibility, normalized addresses,
  0/10/11 boundaries, malformed present metadata, identity preservation, stale-value/wrong-owner
  rejection, failed Save retaining disk bytes/draft, and removed/expired links refusing opening
  before a cached rendering-day refresh.
- Complete native desktop campaign: **28/28** on the ordinary Release bundle. It includes all
  existing shared-state/editor/settings/timer/split/attachment/search/weather scenarios plus links.
  No `ui.stall` event was present in that run's isolated log.
- Focused link-rendering checks are included in that full **28/28** executable. They test positive/zero link
  summaries in favorite/grid/feed, coexistence with tasks/files, value-before-symbol order,
  trailing symbol-column alignment, collapsed defaults, repeated disclosure, hidden-row removal,
  retained ordinary hide/show state, stable heading/count placement and unchanged event bytes.
- External workflow campaign: **3/3 in one run, 113.760 seconds**. The later refinement only
  changed noninteractive desktop section headings and test sequencing; editor/storage/mini
  disclosure paths are unchanged, so this input evidence is intentionally reused:
  `testDesktopEventLinkCancelReopenAndSave`,
  `testEventLinksEditorSaveCancelValidationAndRelaunch`, and
  `testMiniLinksDisclosureAtZeroOneAndTenPreservesData`.
  These exercise ordinary mouse/text input, Save/Cancel/reopen, actual restart, invalid-address
  Save gating, Add/trash, final-link removal and header/trailing-count clicks at 0/1/10 links.

The preceding final-source attempt under Russian layout passed desktop/disclosure but failed
address input: only punctuation was delivered. Its separate failure summary is retained. The
accepted campaign began with a read-only TIS assertion for the existing ABC source after normal
system shortcut selection. Russian was restored afterward. This does not certify every IME.

## Closed desktop failure

The old campaign repeatedly stopped after 15 scenarios when selecting a newly saved favorite:
the event was durable and visible, but its control was unavailable in the test registry. Dynamic
desktop event controls now use the same NSViewRepresentable registration/update path already used
for other dynamic controls. Identity, callback and enabled state update together; stale owners
cannot remove a replacement control. The complete original scenario then passed without removing
assertions, changing product persistence, forcing selection or skipping the affected step.

## Build and screenshots

The native bundle uses the ordinary SwiftPM/build.sh route with
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`, updates disabled, and a build-version
SDK field of 13.0. Xcode's SDK-27 Debug bundle is the external input vehicle, not visual authority.

The twelve current PNGs show Light/Dark collection/feed, link/file/checklist summaries, mini collapsed
and expanded states and the invalid-address editor. They are real isolated application windows,
not HTML. Summary labels place tabular values before native symbols in an 18-point symbol column;
desktop detail section headers share this metadata style, while mini disclosures retain their own treatment.

[Receipt](evidence.json) records source/executable/image hashes. The full and focused manifests
record their source windows and overrides. Static native captures do not certify compositor
animation smoothness; actual reflow overlap is separately guarded before feed capture.

## Scope boundaries

The user accepted the feature and supplied the final number/symbol ordering. No commit, push,
release publication, installation in `/Applications` or production-data migration/reset was
performed. The tester application uses its separate marked home; its data is not a test fixture
for automation and must not be overwritten during packaging.

External browser page content was not inspected after the earlier URL-policy stop. Application
handoff uses NSWorkspace and is covered through the injected success/failure boundary; the user
has accepted the link-opening behavior. Network availability/content of third-party sites is not
part of this app's acceptance. macOS 13 runtime, VoiceOver and every keyboard layout remain outside
this host campaign. No new live model eval/native-hook delivery run is implied by the harness edits.

## Final delivery corrections

The tester wrapper originally executed the Cocoa binary directly. In the delivered tester context
this lost correct status-item/panel anchoring, despite the ordinary bundle's native tests. The
wrapper now uses LaunchServices to open its nested native `NativeRuntime.app`, whose declared
CFBundleExecutable is the real CountdownManager binary. The same marked TestData home is passed
explicitly; production data is not a fallback fixture. The user confirmed that the status-bar
icon and anchoring returned. QA now requires testing the actual delivered entry point.

Desktop saved attachments and links now use one `SavedMaterialHeading` component with required
count and symbol; task progress shares `DesktopSummaryLabelStyle`. Native checks compare all
three section metadata columns. The final full native run passed 28/28 after waiting for the
editor's ordinary initial-title focus before requesting link-address focus; this is sequencing
of the test driver, not a production focus/lifecycle change. Saved test records and attachment
bytes were backed up and retained during native-runtime replacement.
