# Countdown Manager — Architecture

## Purpose

This document maps the current Countdown Manager implementation, including the anchored status-item panel, retained desktop window and single countdown timer.

It describes where responsibilities live and how the major runtime pieces connect.

It does not define product behaviour, engineering philosophy, or task workflow.

User-visible behaviour belongs in `docs/PRODUCT.md`.

Non-obvious durable technical rationale belongs in `docs/decisions/`.

## Package structure

Countdown Manager is implemented as a Swift package with three production targets:

```text
CountdownCore
    ↓
CountdownManagerUI
    ↓
CountdownManager
```

The package also contains executable verification targets for core and UI/state checks.

### `CountdownCore`

Source: `Sources/CountdownCore/`

Owns domain and persistence primitives that do not depend on the application UI.

Key responsibilities:

- civil calendar dates;
- countdown and subtask models;
- domain validation and mutations;
- expiry and optional primary-selection normalization;
- persistence data representation;
- serialized filesystem repository.

Key files:

- `Countdown.swift`
- `CountdownRepository.swift`
- `EventAttachment.swift`
- `AttachmentFiles.swift`

### `CountdownManagerUI`

Source: `Sources/CountdownManager/`

Owns the running macOS application behaviour.

Key responsibilities:

- AppKit application and menu-bar integration;
- application state and persistence coordination;
- the single timer, its local preference state, ticking and completion presentation;
- persisted keep-awake intent and process-owned prevention of idle system/display sleep;
- optional forecast requests, native location and independent weather settings/cache state;
- deterministic presentation logic;
- SwiftUI views and transient view state;
- UI preference state;
- diagnostics;
- runtime support for Real UI Smoke.

Key files:

- `Application.swift`
- `CountdownTimer.swift`
- `KeepAwake.swift`
- `Weather.swift`
- `WeatherLocation.swift`
- `WeatherForecasts.swift`
- `WeatherOpenMeteo.swift`
- `WeatherMETNorway.swift`
- `WeatherWttr.swift`
- `WeatherTransport.swift`
- `WeatherDiagnostics.swift`
- `ApplicationUpdates.swift`
- `TimerCompletionAlert.swift`
- `Store.swift`
- `Presentation.swift`
- `StatusBarImages.swift`
- `Views.swift`
- `MaterialIntake.swift`
- `TextAttachmentView.swift`
- `StatusItemMaterialDragView.swift`
- `AttachmentViews.swift`
- `AttachmentPreview.swift`
- `Diagnostics.swift`
- `DiagnosticPrivacy.swift`
- `DiagnosticArchive.swift`
- `UISmokeControls.swift`
- `UISmokeRuntime.swift`
- `Desktop/DesktopWindowController.swift`
- `Desktop/DesktopDividerGrip.swift`
- `Desktop/DesktopViews.swift`
- `Desktop/DesktopEventViews.swift`
- `Desktop/DesktopPresentation.swift`
- `Desktop/DesktopEventDetail.swift`
- `DesktopSmokeRuntime.swift`

`CountdownRowPresentation` derives card-relative labels from the existing civil-day distance:
Today/Tomorrow/Through N days and Yesterday/N days ago with Russian pluralization. Views use this same label in featured
and secondary cards; the independent menu formatter uses Today/Tomorrow then the numeric Core day
formatter for future dates, and Yesterday/N days ago for retained past dates. The labels remain derived from civil-day distance; `Countdown.keepsAfterDate` owns retention independently of primary selection.

### `CountdownManager`

Source: `Sources/CountdownManagerApp/`

Owns the executable entry point.

`App.swift` delegates application startup to `CountdownManagerApplication.run()`.

## Shell implementation status

The panel implementation uses one borderless `NSPanel` anchored to the status item and one long-lived `NSHostingController`, both owned for the application session. See [the accepted shell decision](decisions/status-item-panel-shell.md). An independently retained native desktop window is created lazily on explicit opening; it reuses the same application-state owners rather than constructing another runtime.

### Ownership

```text
NSApplication / AppDelegate
├── NSStatusItem
├── Store → CountdownData / CountdownRepository → countdowns.json
├── CountdownTimer → UserDefaults
├── KeepAwakeController → one process-owned IOPM assertion
├── WeatherController → location/provider requests and bounded memory cache
├── EventEditorSession → optional panel/desktop editor owner
├── ApplicationAppearance → shared persisted system/light/dark choice
├── WhatsNewWindowController → read-only release help / WhatsNewHistory → isolated-or-standard UserDefaults
├── DesktopWindowController (lazy, retained)
│   └── NSWindow / NSHostingController<DesktopRootView>
│       ├── window-local mode/search/filter/selection
│       ├── native split browser + event details
│       └── one native sheet: EditorView / SettingsView / attachment library + quick preview
└── NSPanel (one strong reference, session lifetime, transient visibility)
    └── NSHostingController (one instance, stable root)
        └── CountdownManagerRootView
            ├── single timer strip
            └── ManagerView
                ├── retained list hierarchy
                ├── internal settings navigation
                └── one internal editing session and its draft
```

Create the panel and hosting hierarchy once. On every explicit show, calculate the panel origin from the current status-item button's screen rectangle, then activate and order that same panel front. Hide it with `orderOut` and route the close command through the same path. Do not assign a new hosting controller/root on hide, close, reopen or ordinary store/timer updates.

SwiftUI view-value recomputation is normal and is not root reconstruction. Keep the list structurally alive while the editor or settings is active; retaining only the hosting controller does not preserve a list removed by a conditional branch. A draft belongs to an explicit editing session, not to window visibility. Save success or Cancel ends that session; hiding does not.

Panel positioning and visibility are shell responsibilities. The borderless panel has no arrow, title bar or traffic-light controls; it is not movable, uses no ordering animation and moves to the active Space only during an explicit show. A synchronous requested-visible flag makes every status-item action resolve immediately: hide only when the panel is visibly presented on the active Space, otherwise show it there. When a requested-visible panel becomes fully occluded during a Space transition, its native occlusion callback clears that request and calls `orderOut`; application deactivation and `NSWorkspace.activeSpaceDidChangeNotification` use the same path as fallbacks. These signals are independent of list/editor/timer state and first responder. Returning to an old Space cannot restore the panel; only a later status-item action can show and reposition it. There is no mouse monitor, responder teardown/restoration machine, persisted scroll offset, draft restoration or per-OS shell abstraction. Existing domain, persistence, disclosure preferences, date refresh, login integration and privacy-safe diagnostics retain their responsibilities.

## Runtime responsibilities

`AppDelegate` owns the status item, panel, hosting controller, `Store`, `CountdownTimer` and
`KeepAwakeController` for the application session. `CountdownManagerRootView` keeps the timer strip
above the retained `ManagerView`; `ManagerView` keeps the list mounted and presents settings or one
internal event editor. Hidden screen content is disabled, excluded from hit testing and hidden
from accessibility. Settings navigation is separate from `EventEditorSession` and cannot become
an updater editor blocker.

### Desktop surface

`AppDelegate` also retains one ordinary `WhatsNewWindowController` for release help. It has its
own native close delegate, an `NSHostingController<WhatsNewView>` and no Store/timer. Safe explicit
panel/desktop opening offers the unseen release; drag-hover and background startup do not.
The delegate checks editor, native sheet, updater and shared persistence/import/export blockers
before presentation. `WhatsNewHistory` records the release ID after `window.isVisible`, using
the same isolated defaults selection as the rest of the runtime. `WhatsNewView.releaseID` is `1.20.4`;
the current section describes dragging a fresh macOS screenshot thumbnail into a local attachment. Manual menu entry bypasses only
the seen check, never the blockers. Appearance subscription and accessibility settings are shared;
the controller never promotes activation policy. Other automated routes suppress the automatic
offer; the focused `--ui-smoke-desktop --ui-smoke-whats-new` route exercises ordinary admission.
Settings provides a service-action entry on both surfaces because accessory-only applications
do not have an ordinary application menu. Mini Settings stays mounted while help is visible.
Desktop Settings retains a one-shot intent through native sheet dismissal. The observed
SwiftUI `onDismiss` callback arrives while AppKit's parent still reports `attachedSheet`;
one main-queue dispatch unwinds that native callback before invoking the same guarded help
action. This is not a timer, polling or an unconditional retry over an active sheet.

`DesktopWindowController` owns one titled, resizable `NSWindow` and its hosting hierarchy.
The first explicit show promotes accessory startup to regular application activation policy;
subsequent shows retain that policy and use normal key/front presentation. Closing does not
demote the app, terminate the application or release
the retained controller/root. Application deactivation and the panel's Space-hide hooks do not
close this ordinary window. `AppDelegate` routes the panel entry, application menu and Dock reopen
to the same controller, and passes the existing Store, timer, updater, weather, keep-awake,
accessibility and visual-environment owners into its root.

The desktop footer's compact-mode callback is distinct from status-item panel toggling.
Explicit switching hides the retained window before opening the panel, with sheet/editor guards;
ordinary status-item activation leaves the desktop visible. Both routes reuse the same panel.
Regular policy persists after the first desktop opening until Quit, including compact-mode
handoff and panel dismissal. There is no pending downgrade flag or policy-changing hide path.
Desktop collection behavior remains the default, unlike the explicitly current-Space mini-panel;
no Mission Control preferences are changed. See [the activation and Spaces decision](decisions/desktop-activation-and-spaces.md).

`DesktopRootView` owns only transient window browsing and one optional native-sheet route. Its in-window command bar
uses native SwiftUI controls directly, without an independent toolbar owner or copied state.
`DesktopEventCollection`
derives the active filtered stable-date ordering, favorite/ordinary partition and month/year sections
from Store data; it does not persist or mutate another copy. Section identity includes the year.
`desktopSelection` reconciles missing visible IDs.
`DesktopEventFlowLayout` places all month headings and ordinary event buttons in one coordinate
system, as adaptive equal-height grid rows or single-column feed rows. Nested month stacks no
longer animate their heights independently from event placements. `DesktopOrdinaryCardLayout`
retains five visual children (calendar, title, metadata, completion container and remaining label)
and repositions them instead of replacing grid/feed content branches. Title and remaining-label
fonts stay constant. Only view-mode changes animate, with a 0.15-second ease-in-out; Reduce Motion
disables that animation. Native divider resizing continues to track the pointer without an added
width animation. Event contents are measured eagerly; no second displayed-event snapshot,
geometry-scale transform or animation scheduler exists.
Both layouts expose a bounded scalar `feedProgress` as `animatableData` and compute intermediate
placements from the two arrangements. This updates actual layout geometry on each animation frame,
not just presentation transforms around already-reflowed text. Measurement work remains linear
in the number of filtered ordinary events; this is not a claim of constant-cost compositor motion.
Text and metadata reflow inside stable clipped containers with leaf-local `animation = nil`
transactions. The containers' placement and bounds remain animated by the parent layout; glyphs
are not individually interpolated between different line breaks or allowed to overflow into
the neighboring metadata while the container changes size.
`desktopMinimumPaneWidth` supplies the one-third/320-point constraint to the native `HSplitView`.
Its direct pane containers retain structural identity; per-event identity is scoped inside the
right container, so changing or clearing selection resets detail-local state without replacing
the native pane or its user-adjusted divider position.
`DesktopDividerGrip` adds a transparent AppKit pointer overlay with a 12-point hit band around
the live divider. It owns only cursor rects and transient drag offset, not a second divider ratio.
Outside the band its hit test returns nil; dragging calls the existing `NSSplitView.setPosition`
so the native delegate still constrains the panes. The overlay never replaces SwiftUI's split
delegate or changes divider drawing. A weak native-view reference and scoped resize observation
are cleared when the bridge leaves the window; failure to find the split leaves native input intact.
`DesktopEventCollection` partitions available ordinary events into ascending future month sections
and descending `pastItems`, rendered as one final `Прошедшие` group. The explicit favorite is
excluded from both partitions, including when retained after its date. Stable equal-date order
uses the stored input position. Mini ordering uses the same future/past rule without sections.
The browser contains selection buttons and summaries; detail actions route favorite, checklist
and confirmed event deletion through the same Store, with pending-persistence and active-editor guards.
`DesktopCalendarLeaf` composes the existing native calendar tile without a desktop emoji overlay.
The desktop footer contains storage information, compact-mode navigation and settings, not a timer.
`DesktopRootView` no longer observes timer ticks; its diagnostic callback still reads the shared
timer owner. The mini-panel timer strip, menu-bar countdown, completion alert and restart guards
are unchanged. There is no second timer or forecast scheduler.
`DesktopEventDateLabel` owns the shared desktop emoji/date composition
for collection, feed, favorite and details; the common calendar leaf has no desktop emoji overlay.
Featured favorites place date and weather inline on a full-width row below the title/calendar
identity, retaining room in narrow panes. Ordinary grid metadata keeps its existing composition.

`DesktopEventCard` derives its optional paperclip/count indicator from `item.attachments`.
The existing fourth ordinary-card layout child holds checklist and attachment summaries; no
extra custom-layout child or stored count is introduced. The ordinary feed composes checklist
and attachment summaries horizontally; grid summaries retain their stacked presentation.
Featured cards use the same indicator in their status row. The accepted priority/limit follow-up places note, `Подзадачи` and attachments
in that order in desktop details, panel cards and the shared editor, with consistent readable
primary-ink section headings. Empty saved attachment sections are omitted; editor controls remain.
`SavedAttachmentSection` exposes saved-file presentation, optional compact disclosure, file opening
and the full-library action. It receives no editor callback or editing-availability state.
`DesktopEventDetail` keeps editor entry only in its header pencil; saved note and checklist
sections contain no duplicate editor actions, including empty states. Expiry explanations belong
only to the editor and deletion confirmation, not ordinary saved sections or file libraries.

Attachment previews derive from repository-owned copies, without persisted preview metadata or
another file owner. Saved summaries use bounded shelves: first four in two desktop columns and
first three in three mini columns, with fixed 88/68-point canvas heights. Library rows retain
44/36-point squares and editor rows retain 36 points. Editor preview resolution accepts either the exact active
saved attachment or the exact metadata registered to its live draft. Repository draft resolution
requires that draft identity, and Store checks draft lifetime before and after awaiting resolution.
The cancellable loader requests Quick Look thumbnails for every non-PDF format, without an
image/movie whitelist. PDFs use a serial actor to render the first page into a bounded bitmap.
Unavailable or failed native previews retain the type fallback. Imported editor files can preview
before Save; reopening resolves their saved copies. Preview preparation remains responsive and
rejects cancelled or stale results.
Preview failure leaves the filename and explicit viewing action available.
Saved summaries derive `Показать все N` from the corresponding four/three-file threshold.
The complete list belongs to a separate bounded presentation: the desktop native
sheet or an internal panel screen whose plain left-chevron Back control matches mini-panel
Settings. `DesktopRootView` owns the desktop library's
event identity and presents the shared `AttachmentListView`; its title is `Вложение` with a
right-side close button. Cross, Escape and backdrop dismissal share the same state boundary.
The dimmed backdrop consumes dismissal input while the pane consumes its empty interior,
following the desktop Settings pattern. Its filename query and scrolling are transient
presentation state, never another saved file collection; event selection resets that state.
Closing returns to the same event/browser context. Header counts are omitted on both surfaces;
the derived footer uses `Файлов: N` for an empty trimmed query and `Найдено: X из N` otherwise.
Search filters only displayed identities and cannot mutate attachments
or checklist completion. The editor keeps the full editable collection.
Removing/expiring the library's owning event dismisses that presentation rather than retaining
a stale owner. The ordinary underlying interface remains mounted but inactive for input and accessibility.
`AttachmentPreviewSession` owns only transient event/attachment selection, origin and cancellable
URL/external-open work. Selection uses stable IDs; adjacent files derive from the current saved
event rather than a second attachment collection. A generation token rejects late results after
navigation, close or reopen. Each surface owns its session; Store/repository retain data ownership.
The shared quick-preview view embeds `QLPreviewView` for the selected repository-owned URL.
Its previous/next buttons assign unmodified Left/Right keyboard shortcuts to the same session
actions, so both input routes share saved-order navigation and boundary validation.
It disables autoplay, creates a renderer per selected identity and explicitly closes it on
dismantling; a closed Quick Look renderer is never reused. URL resolution is distinguished from
native content rendering, because Quick Look has no public ready/error callback for this host.
Missing URL has an application-owned unavailable state; existing unsupported content retains the
native fallback. Explicit external opening uses Store validation again. There is no persisted
preview cache or extra imported copy. Library state stays mounted but inactive behind its preview;
closing returns to that same query/context. Owner removal/expiry closes both; removal of the
selected attachment closes its preview to the surviving source.
The renderer/window lifecycle rationale and observed platform limits are recorded in
[the embedded quick-preview decision](decisions/attachment-quick-preview.md).
`DesktopRootView` uses one SwiftUI `.sheet` for its optional `DesktopSheet` route: editor,
Settings or an attachment-owning event ID. A closing request makes the presentation binding
false while retaining the route until native `onDismiss`; background guards and editor-session
ownership therefore survive the system closing animation. There is no custom animation or
guessed dismissal timer; macOS owns presentation timing and Reduce Motion.
`DesktopSheetBackdropDismissal` is a noninteractive AppKit background view inside Settings/files.
Its scoped local left-mouse-down monitor consumes only clicks in the direct parent content while
that native sheet is attached. It ignores clicks inside the sheet, other windows and nested-sheet
activity. Diagnostics also disables Settings dismissal. Monitor lifetime ends on view detachment,
representable dismantling or deallocation. Editor content has no outside-click bridge and retains
its protected Save/Cancel policy. Removing or expiring a file owner requests native dismissal.

The desktop overview beneath `Впереди` composes the current date and optional forecast for today
in one metadata line, retaining its date position, height and following content geometry for
missing, disabled and loaded weather. Missing/off forecasts expose no placeholder or accessibility content.
`DesktopForecastSlot` keeps the reserved 16-point forecast area in collection grid cards.
Favorites and compact desktop details use a full-width date/forecast line below title/calendar;
details omit an empty saved note and keep the same metadata height while weather changes.
Ordinary feed date/forecast metadata uses one horizontal line,
with weather after the exact date, while its calendar/title align at the top and remaining-time
label sits at the upper right. Missing/off forecasts expose no placeholder or accessibility
content; forecast availability does not select a different card layout. These feed positions
are presentation changes, without another event owner or persisted card state.
The details checklist retains one UUID-keyed `ForEach`; a local animation on committed completion
values moves rows between active/completed ordering over 150 ms. Reduce Motion removes the
animation transaction. Neither mechanism changes shared mini-panel views, Store ownership or FIFO.

`DesktopRootView` serializes accepted checklist/favorite/deletion actions and editor intents in a
window-local FIFO, routing mutations through the unchanged Store. Its own writes do not globally
disable sibling controls. An accepted editor intent reserves `EventEditorSession` immediately,
so close/compact and cross-surface editing are blocked before the sheet opens. Earlier writes
drain first, then the editor reads the latest active identity. External owners or pending writes
pause the queue; ownership changes and deferred Store data publications resume it. Failure clears
remaining intents, reports them and releases an unpresented desktop reservation. There is no
second persistence owner or change to panel mutation rules.

`EventEditorSession` is an enum-backed optional surface owner, not a second draft model.
Panel-compatible `isPresented` reflects only the panel owner; `desktopIsPresented` reflects only
the desktop owner, and `hasActiveEditor` is the updater safety input. Admission cannot replace
another owner and cleanup can release only its own surface. `EditorView` retains the actual
draft in its hosting surface. Desktop Save/Cancel dismiss the sheet and release its owner;
interactive dismissal and parent-window close are prevented while that draft is active.
Panel hide/show retains the existing draft semantics. Both surfaces guard mutations while
the other editor owns the session, preventing a stale form from overwriting concurrent changes.
`DesktopRootView` presents the existing 430 × 560-point SettingsView through its shared native
sheet route. The base hierarchy remains mounted but disabled, excluded from hit testing and
hidden from accessibility through dismissal. The close button, Escape and parent-content outside
click use the same guarded dismissal request; interior clicks do not dismiss it. Selection,
search and divider remain window-local. There is no independent settings window/controller or
new settings store. `Store.saveDiagnostics` attaches its native Save panel to the key Settings
sheet, retaining that host and refusing Settings dismissal until export finishes.
`SettingsView` reuses one navigation button: the mini-panel keeps Back on the left, while the
desktop supplies `showsCloseButton` and places an accessible `xmark` close button to the right of
the heading. Only the desktop supplies the cancel-action keyboard shortcut. DesktopRootView applies
the editor canvas and settings primary ink/accent at its presentation boundaries, keeping both desktop
surfaces visually consistent without changing the shared views' original mini-panel palette.
There is no second settings store or event-editor session.

Views route event mutations through `Store`. `Store` coordinates domain state and asynchronous event persistence; `CountdownData` owns validation/mutations, and `CountdownRepository` owns serialized filesystem access.

Timer mutations route through `CountdownTimer`. It stores one absolute deadline in `UserDefaults`, derives remaining time from the current clock, publishes second-level UI updates only while a deadline exists, and emits a one-shot completion event when a running deadline is crossed. It never writes timer ticks into event persistence and schedules no system notifications.

## Domain model

File: `Sources/CountdownCore/Countdown.swift`

### `Day`

Represents a civil Gregorian date as year, month, and day rather than an absolute timestamp.

### `Countdown`

Persisted event model containing stable identity, title, optional note, date, emoji, subtasks, file-attachment metadata and
the optional `showsWeather` choice. Absent JSON defaults to false; true is encoded, false is omitted.
The flag is an event option, not a separate persisted day type.

`Countdown.attachments` defaults to an empty collection for legacy JSON. The metadata carries no
source path or file bytes; copying and cleanup belong to the repository boundary below.
New additions must respect the 15-file event cap. Legacy collections above 15 remain decodable
and saveable when preserving/removing existing identities; load/normalization does not truncate
them or turn them into a read failure. Add admission uses current draft count, allowing a new
identity only below 15, including after draft removal before Save.
Backward reading of JSON without this field does not imply downgrade safety: 1.15.0 drops unknown
attachment metadata on writes. Attachment associations can only be restored from a matched JSON
and `Attachments/` backup; the presence of copied bytes alone does not recover their event ownership.

### `EventLink`

`Sources/CountdownCore/EventLink.swift` owns UUID, optional name, raw address, HTTP/HTTPS URL
validation and name/domain presentation. Drafts may be incomplete; `CountdownData.save` trims
and validates the collection before mutation. Decode and repository writes also enforce count,
unique identities and usable addresses. Empty metadata is omitted; absent metadata defaults empty.

`EventEditorDraft.links` is the only editor snapshot. `EditorLinkSection` owns field focus and
validation visibility, while the existing Save/Cancel/session guard owns persistence and lifetime.
`SavedLinkSection` is shared by desktop details and mini cards. The mini owns only transient
disclosure state, starting collapsed; desktop remains expanded. `DesktopEventCard` uses the same
neutral summary metrics as attachments for its nonzero link count, and the shared desktop event
accessibility label includes the count without adding another action.
`Store.openLink` revalidates owner
and exact saved value before calling its injected browser-opening boundary (NSWorkspace in the app).
Desktop browser summaries and detail metadata share `DesktopSummaryLabelStyle`: tabular
value/progress first, then a fixed 18-point native symbol column. `SavedMaterialHeading` is shared
by desktop attachments/links and requires their count and symbol; checklist progress reuses the
same metadata style. Mini-panel headers keep their disclosure role.
No browser or network work occurs during rendering, draft editing or save. URLs/names are never
added to diagnostic log fields. The Xcode and Swift package targets include the same sources.

### `Subtask`

Contains stable identity, text, and completion state. Domain limits such as maximum count and text length live with the model.

### `CountdownData`

Mutable aggregate of persisted countdown state.

It owns operations including:

- normalization and expiry;
- optional primary-selection normalization;
- event save and validation;
- event deletion;
- subtask CRUD and completion toggling.

It stores the optional explicit favorite in `primaryID`. Normalization expires only events whose date ended and whose `keepsAfterDate` is false, and clears an expired or invalid selection; it does not populate an absent selection. An empty `emoji` string represents no additional icon, preserving the existing JSON field shape.

`Countdown.usesAutomaticTitle` is persisted with the plain `title`. Missing metadata defaults to
false and false is omitted on encode; no weekday-text inference is performed. `automaticEventTitle`
in Core is the sole Russian Gregorian weekday authority. `CountdownData.save` derives an automatic
title from the selected civil date before committing the candidate snapshot, so title/date/mode
share the existing atomic persistence/revision boundary. Reading arbitrary stored content does not
silently rewrite it; an inconsistent automatic title is corrected on explicit Save.

The timer deliberately does not belong to `CountdownData`: events use civil-day semantics, while the timer uses an absolute deadline.

Forecast values and location coordinates also remain outside `CountdownData`. Weather reads
active eligible event dates; event validation, CRUD, normalization and repository saves do not
perform network or location work.

## Persistence boundary

File: `Sources/CountdownCore/CountdownRepository.swift`

`CountdownRepository` is an actor that serializes production filesystem reads and writes outside the main UI actor.

It decodes and atomically writes `CountdownData` and rejects an older revision when a newer revision has already been accepted by the repository.

`EventAttachment` contains only an identity, original filename and import-time byte count.
`AttachmentFiles`, used exclusively by the same repository actor, stores separate regular-file
copies in `Attachments/<attachment UUID>/<original filename>` beside the event JSON. Validated
filenames and per-folder ownership metadata constrain cleanup to application-owned copies;
original source URLs are never persisted or removed.

Editor-generated draft UUIDs pin imported copies until successful Save or Cancel releases them.
Repository cleanup protects both the last durable attachment references and all active draft
pins. New references must resolve before atomic JSON replacement; cleanup runs only after that
commit, or after a successful load/discard. Failed and superseded writes cannot authorize deletion
of durable copies. Cleanup errors are reported independently through `attachmentCleanupFailed`
and the explicit retry operation; they never turn a committed JSON write into a failed Save.
This is ordered file/metadata persistence, not a claim that the file tree and JSON form one
atomic filesystem transaction. A later successful load collects abandoned imports after a crash.

Persistence rationale and revision guarantees are documented in:

`docs/decisions/persistence-and-user-data.md`

Timer state is intentionally outside this repository. `CountdownTimer` stores only its deadline in local application preferences and never rewrites `countdowns.json`.

## Application state

File: `Sources/CountdownManager/Store.swift`

`Store` is a `@MainActor` `ObservableObject` and is the primary event-state coordinator between UI, domain model, platform services, and event persistence.

It owns or exposes:

- current `CountdownData`;
- current calendar day;
- loading and error state;
- launch-at-login status;
- active event ordering;
- current primary event;
- normal event menu-bar title;
- subtask disclosure state.

`Store` also coordinates application-state revisions and durable snapshots around asynchronous repository writes.

Its attachment operations coordinate the native multi-file picker, draft tokens, imports and
explicit default-application opening. Attachment work participates in the existing pending-work
guard. Saved-file opening rechecks active event membership after resolving the repository URL;
views do not copy or delete files. The shared editor owns the metadata draft, while the repository
owns imported bytes and cleanup. File names, paths and contents are excluded from diagnostics.
The native picker validates the entire selected batch against remaining draft capacity before
requesting any copy. Oversized count selections are rejected without partial import; this does
not replace the existing behavior for later I/O failures, which retains successfully imported
files for retry/Cancel. UI disabled state alone is not the persistence/count-validation boundary.

Date-sensitive event state is refreshed from timers and relevant macOS lifecycle, clock, time-zone, calendar-day, and wake notifications.

Launch at login is integrated through `SMAppService.mainApp`. Settings binds to the existing
`Store.loginStatus` and actions, including the `requiresApproval` System Settings route; it does
not maintain another login preference.

## Keep-awake state

File: `Sources/CountdownManager/KeepAwake.swift`

`KeepAwakeController` is the single `@MainActor` owner of sleep-prevention state
and the process's IOPM assertion identifier. `AppDelegate` creates it once after resolving production
or isolated defaults, and supplies it to the retained UI.
Settings reads its accepted state and requests enable/disable; view rendering and panel visibility
do not acquire or release assertions. `keepAwake.enabled` in the injected defaults stores intent,
independently of the live assertion. Init restores saved ON without rewriting the preference.
Without a preference it starts disabled. The bundle ID/defaults domain remains
`local.countdownmanager.app` across app updates; event persistence is unaffected.

The native boundary uses `IOPMAssertionCreateWithName` with
`kIOPMAssertionTypePreventUserIdleDisplaySleep` at `kIOPMAssertionLevelOn`. This assertion prevents
display idle sleep and also prevents system idle sleep while it keeps the display awake; a second
system-sleep assertion is unnecessary. Its scope follows Apple's
[IOPM assertion contract](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep),
not screen-saver suppression, security-lock prevention, lid-close or manual-sleep control.

Create/release return codes are checked. State changes only after a successful native operation;
a failed create does not expose an active state, and a failed release retains the identifier and
active state for retry with a visible error. Repeated requests for the accepted state are no-ops
and cannot create duplicate assertions. Explicit disable and actual application termination
release the assertion; explicit disable saves OFF, whereas termination preserves saved intent.
A failed startup restore keeps saved ON and reports inactive/error; explicit ON retries and OFF
clears the failed intent. `canDisableRestoration` derives the error/inactive/saved-ON condition from
the owner; Settings then exposes `Не включать при запуске`, without storing another preference.
Cancelling an update termination retains the running session and its
assertion. The OS assertion belongs to the process and cannot survive its exit. Timer mutations,
Back, panel hide/show, application deactivation and Space changes are independent of this owner.

A narrow injectable create/release boundary allows deterministic failure, duplicate-request and
lifetime checks without preventing real sleep. Runtime verification may exercise the real native
boundary only for a bounded interval and must release any assertion it creates.

## Timer state

Files:

- `Sources/CountdownManager/CountdownTimer.swift`
- `Sources/CountdownManager/TimerCompletionAlert.swift`

`CountdownTimer` is a separate `@MainActor` `ObservableObject` because its duration/deadline semantics do not belong to the civil-day event model. `TimerCompletionAlertPresenter` owns the short-lived, non-activating AppKit completion alert and plays the bundled `Resources/TimerFinished.mp3` sound, with the system `Glass` sound as a fallback.

The alert retains a layer-backed `TimerCompletionAlertView` that derives its AppKit background,
text, border and alarm-symbol tint from the shared `AuroraInstrument` palette. The existing
`AuroraAccessibilitySettings` owned by `AppDelegate` supplies contrast to both the primary UI and
the alert. The alert observes that shared value; effective appearance, window attachment and each
presentation also refresh the same view's colors. Its non-activating panel and first-click
forwarding remain owned by the existing presenter and content view; appearance changes do not
modify timer state or create another window.

The same view owns a single Core Animation transform loop on the alarm image's layer. A short
burst of bounded tilts/lifts is followed by a resting pause. Its request flag distinguishes active
presentation from the still-visible fade-out phase. Presentation resets and starts the cycle;
every dismissal clears the request and removes the animation before hiding. Live Reduce Motion
uses the shared settings owner and keeps the icon static. The card, labels and status-item motion
retain their existing owners and geometry.

It owns:

- the optional persisted deadline;
- derived idle/running/finished state;
- one-second presentation refresh while a deadline exists;
- timer menu-bar title/tool-tip values;
- a one-shot completion event when a running deadline is crossed.

A persisted deadline in the past represents the finished state until the user deletes the timer. It does not replay the completion alert on launch. A stored future deadline beyond the longest two-hour preset is treated as invalid and cleared rather than converted into overflowing display seconds. Deleting removes the local deadline and dismisses a visible completion alert.

## Application updates

`ApplicationUpdates.swift` owns one `SPUStandardUpdaterController` from pinned Sparkle 2.10.0.
It starts only when the bundle has a valid HTTPS feed, a 32-byte public key and signed-feed/archive
verification enabled. Sparkle owns scheduling, preferences, download, installer and update UI.
The application uses `automaticallyChecksForUpdates` directly rather than maintaining another
update preference. System profiling and silent automatic installation are disabled.

The same owner implements `SPUStandardUserDriverDelegate`. `standardUserDriverWillHandleShowingUpdate`
and `standardUserDriverWillShowModalAlert` synchronously ask `AppDelegate` to hide the retained panel
and temporarily set its level to `.normal`. Manual check/refocus and deferred-install entry points
do this before invoking Sparkle because their progress windows have no before-show delegate hook.
Explicit panel reopening keeps the retained hierarchy and ordinary level during that session.
`standardUserDriverWillFinishUpdateSession` restores `.popUpMenu` on the next main-queue turn after
Sparkle's window-closing callback unwinds, without showing the panel. No Sparkle window is inspected,
reordered or assigned another level. The application-owned deferred-install modal uses the same
hide boundary. Its explicit return button calls `AppDelegate.returnToActiveEditor()`: an active
desktop editor takes priority, followed by an active panel editor, an already visible desktop
window, then the panel. The modal never retries itself.

`AppDelegate` owns `EventEditorSession`, the single observable owner of the active editor surface shared with
`ManagerView` and `DesktopRootView`. Draft fields remain owned by the `EditorView` on the admitted
surface. The updater reads that session, the timer phase and `Store.hasPendingPersistence` through
an explicit main-actor safety closure.
It stores Sparkle's native postponement continuation while blocked. Explicit Install rechecks
safety before consuming the continuation once. `willInstallUpdate` marks update termination;
`applicationShouldTerminate` cancels it if activity appears in the remaining installation window.
Explicit application Quit clears that update-specific flag before its normal termination request.

`DesktopSheetTerminationPolicy` configures only the attached desktop sheet window. Read-only
Settings and file sheets set `preventsApplicationTerminationWhenModal` to false, so Sparkle's quit
event reaches `applicationShouldTerminate`. Editable event/text sheets retain true. The bridge
applies on window attachment and context updates, without scanning windows or introducing an
update-specific dismissal coordinator. Existing editor/persistence/timer/export safety remains authoritative.

SwiftPM and the Xcode project link Sparkle; application bundles embed the complete framework.
`build.sh` stages, configures and signs nested components inside-out before replacing its build
output. `scripts/update_tools.py` validates release configuration and key matching, creates a
symlink-preserving ZIP, and uses Sparkle's tools to sign/verify the archive and appcast.
No production private key is present in source or application bundles.

An explicit update-test bundle uses `local.countdownmanager.update-test`, a separate Sparkle defaults
domain, and a marked isolated home baked into both bundle plists. `UISmokeConfiguration` validates
that home before Store, timer or diagnostics start; test defaults and logs use it after relaunch too.
It keeps normal shell lifecycle callbacks. Only this validated test configuration accepts loopback
HTTP; production channels require HTTPS. Fixtures exercise the standard Sparkle controller.

## UI preference state

Files:

- `Sources/CountdownManager/Presentation.swift`
- `Sources/CountdownManager/Store.swift`

Subtask disclosure state is separate from `CountdownData`.

`SubtaskDisclosurePersistence` stores per-event values in `UserDefaults` and `SubtaskDisclosureCache` supplies observable per-event state to the SwiftUI layer.

The timer also uses `UserDefaults`, but its deadline is durable timer state rather than an event or checklist preference.

`ApplicationAppearance` in `SettingsView.swift` owns the `appearance.selection` preference and
publishes `system`, `light` or `dark`. AppDelegate creates one instance from the same standard or
isolated defaults used for other local preferences and injects it into both interface roots.
Both roots resolve SwiftUI color scheme through this owner; AppDelegate applies the matching
native appearance to the panel and retained desktop window. System removes the explicit override.
The isolated visual override takes priority without changing the stored choice. `NSApp.appearance`
and system menu-bar styling remain untouched; no parallel appearance owner is introduced.

Global weather enablement and the selected automatic/manual location are local preferences owned
by `WeatherController`. They are independent of each event's persisted `showsWeather` flag.
Fresh defaults disable weather and select Automatic. Device coordinates and forecasts are memory-only.

## Weather state and requests

`AppDelegate` owns one main-actor `WeatherController`; Store retains event/persistence ownership.
Views only read weather snapshots. Event demand and explicit successful editor Save are separate
boundaries, preserving no-prompt restoration and foreground first-use permission behavior.

- `Weather.swift`: global preferences, native location boundary, parallel source lifetimes, progressive
  publication, per-source cache freshness and cancellation/generations. The injected legacy forecast
  closure remains the synthetic-provider boundary for isolated runtimes; production uses three sources.
- `WeatherForecasts.swift`: query/calendar intervals, optional metrics, categories and pure normalization.
- `WeatherOpenMeteo.swift`: explicit timezone/date range, Celsius daily max, WMO and liquid `rain_sum`.
- `WeatherMETNorway.swift`: identified complete Locationforecast; non-overlapping periods, unit checks,
  interval maxima and complete hourly-forecast max fallback, liquid-only precipitation and symbols.
- `WeatherWttr.swift`: keyless j1 response; supplied civil dates/maxtempC and exactly eight 3-hour
  accumulated precipitation slots summed once. Frozen/mixed/unknown phase leaves rain missing.
- `WeatherTransport.swift`: ephemeral HTTPS session, optional conditional Last-Modified request,
  Expires/Retry-After parsing and 304 revalidation. Cookies, credentials and disk cache are disabled.
- `WeatherLocation.swift`: coarse native location and ten fixed cities with IANA zones. No IP lookup.
- `WeatherDiagnostics.swift`: fixed technical log formats, safe error classification and full-day
  usable counts. Its injected sink defaults to no-op; production `AppDelegate` selects `.journal`.

A stable Gregorian query captures the selected zone and sixteen local dates. Manual zones come from
cities; Automatic currently uses the device zone, with the corresponding limitation documented in
PRODUCT. Normalization records actual coverage. MET one/six/twelve-hour periods cannot double-count;
full-day hourly fallback requires every valid hourly slot, with no sparse interpolation or intra-hour
peak claim. Source fixed 24-hour days are not relabeled as complete DST 23/25-hour days.

The pure aggregator prefers full-day records, otherwise compares only identical partial periods.
Numeric medians ignore missing values; category majority has a deterministic wet tie preference.
The controller's plain badge only publishes full-day consensus. Three sources are separately hosted
APIs, not guaranteed independent models. Rain is optional liquid mm, not probability or snow depth.

Cache identity includes rounded coordinates, stable zone and requested start day. Four contexts hold
at most one bounded batch per source. Each source has its own freshness and next-request deadline;
304 reuses only an existing matching-context batch. Source failure retains still-fresh previous data.
One parent task with a structured task group coalesces a location/range request and publishes each
completion without waiting for other services. One cancellable scheduler wakes at the next freshness
or retry boundary; generation and schedule identity reject late callbacks after OFF/location/stop.
Deleting the last eligible event also cancels provider children, location and the scheduler.
Deleting one of several events/days retains the useful shared request. Current demand gates every
badge and publication; late responses from a cancelled generation cannot repopulate the cache.

Transport and synchronous decoding inside its nonisolated async function execute on the generic
executor in the project's Swift 5 mode, following
[SE-0338](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md).
The MainActor controller snapshots Sendable fresh batches, query and demanded day keys for
`WeatherNormalizer.aggregateDemanded`. That nonisolated async helper computes only demanded dates,
checking cancellation between dates; cache and UI publication remain on MainActor.
A separate computation revision/input snapshot rejects paused work after subset deletion or a newer
provider outcome, even when the shared request generation remains unchanged. Superseded tasks cancel.
Expired/deleted values are withdrawn synchronously before awaiting a replacement computation.
Adapters check cancellation before/after JSON decoding and between substantial normalization loops;
MET coverage recursion also checks. JSONDecoder/JSONSerialization cannot be preempted within a call;
payload limits and checkpoints bound the remaining work. No detached tasks or new actors are added.
`WeatherHTTPMetadata` holds parsed Date/Age/Cache-Control/Expires, bounded in-memory validators and
receipt clocks. Raw headers/validators never enter logs. max-age overrides Expires; age includes
request duration and resident ContinuousClock time. Field presence survives 304 merges; conflicting
validators/orphan bodies force a bounded unconditional GET. Missing 304 freshness does not restart
the local heuristic. no-store discards the body, no-cache has zero reusable lifetime, and stale is
never published. Legacy provider fields remain only as compatibility for synthetic fixtures.

`WeatherRequestPolicy` is pure value scheduling logic. Its three SourceState records live in the
controller, outside the four-context LRU: rolling six-start/600-second budgets, consumed rapid slots,
ordinary/expired backoff stages, serverNotBefore and providerCooldown. OFF/city/context eviction do
not clear those gates. A quiescent source may reset counters after 1800 seconds without starts;
ongoing upper-stage failures do not accidentally restart rapid series every 1800 seconds. Admission
is rechecked immediately before dispatch; blocked/cancelled old-generation tasks cannot clear a
new fetch owner. A late observed HTTP server gate can extend source-wide timing, but cannot alter
cache/publication. One parent group still serializes batches and reevaluates overdue work on drain.

Freshness, policy nextRequest, serverNotBefore/providerCooldown and budget deadlines are distinct
monotonic quantities. One scheduler selects the earliest necessary expiry/admitted attempt, sleeping
in at most daily slices. NWPathMonitor is a lifecycle-bound signal adapter on one utility queue,
not another cache/service owner or proof of HTTPS reachability. Its revision rejects stale callbacks.
Offline preserves expiry scheduling; debounced recovery cannot erase gates or rapid usage. Energy
and path cost are checked both when selecting rapid backoff and before admission. Wake/clock/day/zone
notifications enter the existing store/refresh boundary; suspicious clock spans/queued pre-jump
responses cannot publish fresh data. No new provider, detached task, actor, disk file or UI status.

Diagnostics retain the existing bounded nonblocking writer. Only enum/boolean/bounded numeric
fields describe header parse/freshness, signed relative times, retry category, admitted attempt index
and consumed rapid allowances. URLs, city/coordinates, event content, raw errors, ETag/Last-Modified
and body contents are excluded; no synchronous flush or UI disk I/O is added.

The app's weather UI consists of the switch, location menu, editor checkbox and plain symbol/temp.
Source, licence and privacy documentation stays here and in README rather than app controls. The
personal-use scope does not imply provider terms have disappeared: see
[Open-Meteo terms](https://open-meteo.com/en/terms), [MET terms](https://api.met.no/doc/TermsOfService),
[MET JSON format](https://api.met.no/doc/ForecastJSON), and
[wttr/WWO schema](https://www.worldweatheronline.com/weather-api/api/docs/local-city-town-weather-api.aspx).
Any later distribution requires checking the applicable source attribution/licensing requirements.

`currentDayHeaderLabel` formats the existing published `Store.today`; the view removes the app name
and shows a system-15-semibold date above the secondary-11 `eventCountLabel` count, separated by
3 pt. The helper applies Russian event-count endings without storing another count or date.
Existing Store refresh boundaries drive midnight/wake/reopen. `applicationVersionLabel` reads the
running bundle's short version for the small secondary Settings footer; it has no version literal.
The isolated header scenario substitutes a fresh synthetic Store into the actual retained panel's
hosting surface, observes its caption/count across midnight and restores the original host; production
clock/state and public Store access control are unchanged.

## Presentation layer

File: `Sources/CountdownManager/Presentation.swift`

Contains deterministic UI-facing transformations and state that do not require SwiftUI view construction, including:

- user-facing strings, including Russian event-count endings;
- compact emoji presets;
- row presentation values;
- human-readable dates;
- calendar-leaf month/day labels and list-only suppression of the default calendar emoji;
- active-event ordering for presentation;
- normal event menu-bar title generation;
- editor validity checks;
- editor draft representation;
- day-creation defaults and Russian calendar weekday titles;
- disclosure preference persistence.

Timer-specific remaining-time formatting stays with `CountdownTimer.swift` because it is independent of event presentation semantics.

## SwiftUI views

Files:

- `Sources/CountdownManager/CountdownTimer.swift`
- `Sources/CountdownManager/Views.swift`
- `Sources/CountdownManager/AuroraInstrument.swift`

`CountdownManagerRootView` is the stable SwiftUI root inside the retained hosting controller. It
composes the 60-point timer strip with the 540-point `ManagerView`. The idle timer selector uses a
quiet accent surface and outline while Play retains a filled accent; the existing selection,
matched-geometry motion, keyboard focus and deadline owner are unchanged.

`AuroraInstrument` supplies the shared warm light/dark palette, contrast variants and control backgrounds. Event rows compose a larger right-hand calendar leaf only for the explicit favorite and a smaller left-hand leaf for all other events. `CountdownRowPresentation.isFeatured` derives directly from `isPrimary`; no separate first-row or nearest-event identity controls prominence. Without a favorite, every row is compact, including today. `Store.primary` retains its existing favorite-or-nearest lookup for other callers; it does not decide row styling. The menu bar has an independent derived `StatusBarPresentation` in `Presentation.swift`: only the active explicit primaryID supplies an event, while empty/legacy calendar emoji selects K1 and absent favorite selects Mars. No saved selection state is introduced. Calendar labels and optional list emoji remain derived from `Presentation.swift`.

Event rows use a 23-point Georgia featured title and a 54 × 65 right-hand calendar leaf; secondary
rows use 14-point titles and 42 × 51 left-hand leaves. Additional emoji is composed with the title;
favorite/edit actions remain separate 28 × 28 controls. Secondary headers use a 51-point GeometryReader
with the actual available title width. Native 14-point semibold string measurement (including emoji)
selects one-line title/date/weather or two-line title/inline metadata composition; no character-count
heuristic is used. Title/meta line slots are 17/14 points with 3-point spacing. The 51-point calendar
and text/action block align in both layouts. Actual forecast SF Symbols remain bound to the existing
weather getter, without new requests. Featured weather and its conditional middle dot are in the
full-date HStack under the title, including today; the separate countdown contains no weather.
The featured Georgia 23 title, 54 × 65 right leaf and 28-point actions keep their existing metrics.
Notes use an
unlimited-height12-point block below the entire header at full content width; checklists follow.

`Store.showsEmptyEventList` derives genuine empty content from active events and
`eventCreationIsAvailable` (successful load/read, no persistence recovery). Recovery-state changes
publish so the UI can leave the guarded state when recovery completes; no second empty-state owner
or persisted preference is introduced. Empty content replaces the whole header/list area with the
existing small calendar leaf, copy and three day-creation actions, centered above the
unchanged footer. The timer remains outside ManagerView. The empty-state buttons reuse `createDay`
and `dayPreset`, including weekday titles that follow the date until manual editing and weather ON.
The ordinary plus route retains its blank title and weather OFF.
Both use the retained internal editor and its normal draft/save boundary. The choose-date route
reuses the native date field with a prompt; text fields keep only their system bezel/focus.

An event surface groups the row and its checklist as one block. The full-width disclosure button
places a chevron left of `Подзадачи` and the completed/total count at the right; it does not wrap
the favorite/edit actions. `CountdownRowPresentation.allSubtasksCompleted` derives nonempty/all-done
from its existing active/completed groups. Only the trailing counter group receives the semantic
green from `AuroraInstrument.todayColor`, with a decorative SF Symbol checkmark. The existing
disclosure accessibility label conveys completion; no second action or stored state is introduced.
Native checkbox row colors and event lifecycle remain unchanged.
The cached `SubtaskDisclosureState` remains its sole owner. Standard
SwiftUI layout and opacity transitions animate presentation without another expanded state or
animation timer.

Each checklist row uses one native checkbox `Toggle` with the actual subtask text as its label.
The label expands to the available row width and defines a rectangular content shape, including
its trailing empty area and vertical row spacing. The binding routes one activation to
`Store.toggleSubtask`; no outer tap gesture duplicates the checkbox action. Completed grouping,
stable identifiers, persistence and editor text bindings retain their existing owners.

`ManagerView` owns internal settings navigation and keeps the list alive beneath settings and
the editor. `EventEditorSession` remains the sole owner of editor visibility; `EditorView` owns
its draft, date, primary selection and inline deletion confirmation. Save success or Cancel ends
editing; hiding the panel does not. An unavailable event retains its draft and cannot be saved as
that event. Settings entry is guarded to the list, and Back preserves the list's existing scroll
view without storing or reconstructing a second browsing state.

The list's one-row footer contains the storage label, a 14-point gear before Quit and Quit.
Settings groups existing owners into `Приложение` (login, Sparkle automatic checks, keep awake),
`Погода` (enablement/location) and `Обслуживание` (manual update and diagnostic export).
The export action obtains an on-demand context closure passed from `CountdownManagerRootView`
through `ManagerView`, rather than adding timer observation to the list or taking snapshots during
rendering. A deferred update replaces the manual-check
action with the existing explicit install entry point. Login approval and operation errors remain
visible. There is no settings draft or Save/Cancel; accepted owner state is shown immediately.
The timer strip stays outside this screen navigation at the top of the same 390 × 600 panel.

The header calendar control reveals inline `Сегодня`, `Завтра` and `Выбрать дату` day creation choices;
the existing `+` still opens ordinary event creation directly. Day creation supplies today's date
for `Сегодня`, tomorrow for the other routes, no additional emoji, an automatic Russian weekday
title and empty note/subtasks. Ordinary creation initially selects tomorrow and a custom empty title.
The same native date field accepts today/future dates; an existing retained past event may keep
its saved date. The core mutation boundary rejects new or changed past dates. Today's expiry notice
appears only with retention off. The third event checkbox edits `keepsAfterDate` in the draft; a
past retained draft with retention turned off uses the existing inline deletion confirmation and
Store deletion rather than an ordinary Save. Cancel and write failures retain the editing context.
`EventEditorDraft` restores the persisted title mode. Its user-input setter disables automatic naming
only when text actually changes; date updates and the explicit `Название по дате` action mutate the
draft directly. The action shares the title's label row, adding no second native field outline or
additional owner. Automatic mode is displayed there as `По дате`.
Date changes regenerate automatic names for both new and existing events; manual names remain
untouched. The explicit reset changes no sibling event fields. Creation actions preserve an open
editor, and the underlying list stays mounted. Successful Save persists the mode with other fields;
Cancel or failed persistence preserves the prior durable snapshot. The Store continues checking
the current civil day and existing identity at its mutation boundary. There is no separate day type,
week state, title-guessing migration or template library.

The editor uses a 21-point Georgia heading in a 49-point header. Its scrolling form keeps the
existing retained draft; Delete, Cancel and Save share the 58-point fixed footer, with deletion
confirmation presented inline above it. The native note field remains visible for empty and filled
notes, with `Заметка · необязательно`, `Пара слов о событии` and a live `0/150` character count below the field.
There is no note disclosure state; its text stays in the existing retained draft. `NoteEditor.swift`
is a narrow NSViewRepresentable boundary around an NSTextView and native bezel NSScrollView. It
reserves 3 native lines, grows to 6 and then scrolls. AppKit owns selection/undo and marked text;
committed input stays whole in the draft, including above the save allowance. The bridge only requests focus
on a distinct explicit note-focus request after releasing the SwiftUI field focus, and does not rewrite matching or marked native storage.
`CountdownNote` in CountdownCore supplies the shared raw-grapheme allowance: 150 for a new note,
or max(150, current saved active event note count) for an existing identity. `CountdownData.save`
looks up that current record; `editorCanSave` and the counter color use the same rule. No schema
field, migration, legacy cap copy or second note owner is added. Unchanged saved notes are preserved
exactly; changed/new notes keep existing outer trimming. No edits persist before Save.

Emoji selection is an independent outlined full-width `Значок` field, with a disclosure chevron
and a separate clear button inside the same boundary. A 13-point gap separates it from the weather
and favorite native-checkbox group; subtasks occupy their own following section. Empty selection
hides the clear button. Compact row spacing prioritizes editable subtask text; character-limit
feedback remains available while editing or when invalid.

Editor subtask rows use identity-scoped layout/opacity animation for Add/Delete. Their text bindings
resolve stable UUIDs against the same parent draft and retain an immutable outgoing value while a
removed row finishes its transition; setters ignore absent UUIDs. Removed rows lose input and
accessibility eligibility immediately. Deferred Add focus checks membership before scrolling or
focusing. Typing does not change the identity array and therefore does not animate the block.

`EditorView` owns one transient picker state: closed, compact presets or a catalog page. The selector starts closed; `Все значки` advances from compact presets to the inline catalog. The catalog retains five named six-row/eight-column sets (`Общие`, `Дети`, `Работа`, `Транспорт`, `Праздники`), conventional previous/next controls, page dots and horizontal drag navigation. Grid dimensions fit the scrolling editor's inner width. Choosing or clearing an emoji replaces only the draft value and closes the picker, resetting navigation. Native layout/opacity transitions animate disclosure for 200 milliseconds while page changes slide horizontally; both respect live Reduce Motion. The stable picker boundary excludes closed content from hit testing and accessibility, including during removal transitions. Emoji selection does not use an editable text field, first-responder handoff or an application-owned popover. Subtask text changes use the same editor; primary selection and completion remain in the list. Errors are presented inline. The mini-panel presents its editor internally without a sheet; the desktop presents the same `EditorView` in a sheet. Neither surface uses application-owned action/emoji popovers.

## AppKit application shell

File: `Sources/CountdownManager/Application.swift`

`CountdownManagerApplication.run()` configures `NSApplication` as an accessory application.
`AppDelegate` creates one status item, one borderless key-capable `NSPanel`, one `Store`, one
`CountdownTimer`, one `KeepAwakeController` and one hosting controller at startup. It retains them
through the session, starts diagnostics and supplies isolated test defaults/data when requested.

The shared appearance subscription applies the selected System/Light/Dark mode to `NSApp` as well
as the retained application windows, so native menus, standalone dialogs and Sparkle UI inherit
the app choice. The status item retains its system-owned effective appearance. `AuroraInstrument`
supplies the neutral Graphite dark palette (`native-calendar-graphite-v2`) to every custom surface;
Light and semantic accent/state colors retain their existing recipes. File dialogs use their
current host as `appearanceSource`, falling back to the retained panel, and the completion-alert
presenter weakly uses that panel as its source. This preserves live appearance inheritance without
recreating windows or changing data ownership.

`AppDelegate` merges Store and timer change notifications to update the status item. Idle updates apply the derived menu title, optional appearance-matched Mars image or K1 template image and tooltip together, clearing the previous image/title when switching to emoji or an image-only state. `StatusBarImages` owns cached 18-point vector PDF images: `MarsMenuLight.pdf` and `MarsMenuDark.pdf` retain the approved neutral-body/red-stripe colors, while `CalendarMenu.pdf` remains a monochrome template. Mars selection uses the status button's effective appearance; appearance changes refresh the status image independently of Store or timer mutations. A zero-frame, non-interactive `StatusItemAppearanceView` child relays the documented `viewDidChangeEffectiveAppearance()` callback from the actual button hierarchy; it is excluded from accessibility and hit testing. `Resources/MarsMenuLight.svg`, `MarsMenuDark.svg`, `Mars.svg`, `Calendar.svg` and `AppIcon.svg` document the editable identity; `scripts/generate_icons.py` is the shared geometry authoring/generation source; `build.sh` packages the menu PDFs, legacy `AppIcon.icns` and precompiled `Assets.car`. `CFBundleIconName=AppIcon` selects the system icon catalog; `CFBundleIconFile=AppIcon` retains fallback lookup. `Resources/AppIcon.icon` contains theme-specialized vector layers, while `scripts/compile_app_icon.py` uses Xcode actool to regenerate the catalog and verify Default/Dark stacks plus legacy sizes. Normal source builds copy the committed catalog and do not require actool. A running or finished timer temporarily overrides the normal event status title and shows the `alarm.fill` SF Symbol next to the remaining time; the finished state shows the symbol alone. While the timer runs, the status item breathes with a gentle repeating opacity pulse. The finished alarm receives a repeating Core Animation rock — each tilt pivots on its own bottom corner with a tiny lift, so it hops from foot to foot — until deletion, or an opacity pulse when Reduce Motion is enabled. It subscribes to the timer's one-shot completion event so the five-second application-owned alert and sound are presented while the accessory app is active.

The Dock application icon shares the menu Mars body/stripe colors: Light uses tile `#f5f1e8`,
body `#303038` and stripe `#b44e38`; Dark uses tile `#211c19`, body `#f0eee9` and stripe `#ef9b81`.
The stripe is colored, while the crater holes expose the tile. The generator maintains the SVG,
ICNS fallback and Icon Composer source layers; the compiled catalog remains a packaged resource.

`AppDelegate` owns `MarsOpeningAnimation` in `Sources/CountdownManager/MarsOpeningAnimation.swift`
and starts it after successfully showing the panel or desktop window. The owner installs one finite
Core Animation transform on the status button layer, outside Store and persisted preferences.
Each accepted opening starts or restarts one linear 12-second full revolution; ordinary status
updates do not start new cycles. The effect is admitted only for the actual idle Mars representation.
Favorite or timer rendering cancels it immediately without resuming it later in the same cycle.
Reduce Motion suppresses the effect, stops an active cycle and does not auto-restart when disabled.
Completion, Reduce Motion and application termination remove the status animation.
The Dock remains the ordinary static system-rendered application icon with the new palette. There
is no animated Dock content view, temporary icon replacement or per-frame Dock redraw. Panel/window
ownership, application activation policy and persisted state remain unchanged.

Status-item actions toggle the requested visibility state immediately. Show orders out any stale visible instance, positions the panel under the current status item, activates the accessory app and makes the panel key/front. Hide, full occlusion while requested visible, application deactivation, active-Space change and Command-W clear requested visibility and call `orderOut`. Ordinary startup does not open it. Isolated harnesses suppress these automatic lifecycle callbacks while verifying retained panel/hosting/root/list/editor state; observable anchoring, app-switch, Space and real status-item interaction remain release manual acceptance.

A standard AppKit application menu supplies text-editing commands, Quit and the native close command. The panel's native occlusion callback closes a visually departed panel even when a rapid Space transition is reversed before the workspace posts its completed-change notification. The mini-panel has no centering, user movement, frame persistence, mouse monitor, workspace polling, key/responder-driven visibility hook, sheet-end observer, forced first-responder assignment or root reconstruction. The retained desktop window is centered once when created and uses ordinary native window movement and resizing; its separate lifecycle is described above.

Product semantics live in `PRODUCT.md`; accepted rationale lives in `decisions/status-item-panel-shell.md`. The superseded standalone-window, popover and historical popup decisions retain prior evidence only.

## Diagnostics

File: `Sources/CountdownManager/Diagnostics.swift`

`DiagnosticLog` owns a dedicated utility queue for Unified Logging, filesystem access and rotation.
Callers submit best-effort bounded messages: nonblocking admission accepts at most 512 pending
records and truncates each message to a 4 KiB UTF-8 input budget; contention or pressure may drop
records. A later admitted write can report an aggregate `diagnostics.dropped` count. Formatting,
OSLog and file writes remain off the UI actor. Production paths use asynchronous queue operations;
`flush()` is retained only as an isolated verification helper, never a normal UI or quit barrier.
The journal retains current and previous generations with a 512 KiB per-generation bound.

`DiagnosticPrivacy` classifies errors and filters exported historical lines through fixed event,
field and value allowlists. Unknown/free-form legacy text becomes a redacted marker rather than
being copied into an archive. `DiagnosticArchiveExporter` owns one explicit export's temporary
files on a separate utility queue. It writes redacted current and, when present, previous logs and
`summary.txt`, creates a ZIP with bounded process lifetime and archive size, then commits through
a sibling staging file and atomic rename. Cancellation and pre-commit failures clean temporary
files and preserve an existing destination. No event file or defaults dump enters the payload.

`Store.saveDiagnostics(context:)` owns `NSSavePanel` presentation and the exporting UI state.
Settings requests a weather snapshot first; after a confirmed destination, the on-demand context
captures only technical timer/updater/weather state and Store aggregate/persistence state.
The exporter adds safe app version/build, macOS version, architecture, UTC time and offset.
Journal snapshot reads are serialized after admitted writes without `queue.sync` on production UI
paths. Cancel writes no archive, concurrent export requests are suppressed, and failure is exposed
through the existing visible error owner. The explicit save dialog is the only new native dialog;
settings navigation, event editing and the retained shell keep their existing lifetimes.
The general in-process runtime check exercises native open/Cancel/reopen/Cancel only. It does not
invoke the save panel's `ok(nil)`: that programmatic driver hung in an isolated AppKit reproduction
and is not reliable evidence for the physical Save route. The ZIP worker is checked independently
below the dialog boundary. Separate external 1.18.0 acceptance exercised actual Save and ZIP
inspection under the identified ABC input source; see `docs/VERIFICATION.md` for its provenance
and the affected-only driver correction. This does not broaden the in-process driver's scope.

`WeatherDiagnostics` uses this existing journal through an injected Sendable sink. It records:

- `weather.state`: init/configuration/demand/shutdown reason, enablement, automatic/manual mode and
  demand/source counts; `weather.location`: fixed request/permission/result categories;
- paired `weather.request.start` / `weather.request.end`: fixed service identifier and random
  request UUID, elapsed milliseconds, HTTP status or `none`, received byte count or `unknown`,
  decode outcome, decoded-day count, full-day count, full days with temperature/condition and
  their usable intersection;
- `weather.source`: fixed success/failure/not-modified result, cache state and seconds until
  freshness/retry boundaries; `weather.schedule`: scheduled delay or cancellation;
- `weather.publication`: demanded/usable counts; `weather.computation`: classified aggregate error.

`AppDelegate` requests a `.launch` weather snapshot after supplying initial event demand, including
after Sparkle relaunch. The controller also records bounded snapshots around normal state changes
and settled work. The Settings `Сохранить диагностику…` action requests a `.diagnostics` snapshot
before `Store.saveDiagnostics(context:)`. The asynchronous export snapshot is ordered after prior
admitted records; it does not block the UI while draining the journal.
`WeatherDiagnosticSnapshotReason` restricts snapshot reasons to launch, diagnostics and
settled. `weather.snapshot` contains a fixed result (`disabled`, `no_eligible_dates`,
`location_pending`, `location_unavailable`, `loading`, `available`, `no_usable_data` or `stopped`),
enablement/mode, eligible demand and usable counts, request/location/computation pending flags,
and fresh/failed source counts. Usable counts require unexpired published data and current eligible
demand. Snapshot collection is observational: it reads this state without refreshing providers,
requesting location or changing permissions, preferences or cache entries.

The controller requests `.settled` snapshots after ordinary refreshes, location completion,
provider task-group completion, consensus success/error and shutdown. Identical consecutive
automatic snapshot fields are suppressed, while `.launch` and `.diagnostics` explicitly record
even unchanged state. Only the last diagnostic fields are retained for this suppression.

Errors use a fixed allowlist; URL failures include only numeric `NSURLErrorDomain` code and a
timeout/offline/connection/cancelled/other category. Request URLs, coordinates, selected city names,
event content or day keys, response bodies, headers, NSError userInfo, localized messages and
arbitrary error descriptions are excluded. Usable source-day counts require an exact full query
interval with both temperature and condition, matching the badge's completeness requirement.

Records follow actual work and state boundaries, never view rendering, timer ticks or forecast
getters. Location result and publication count records suppress identical consecutive values;
configuration/demand records require a change, and scheduling records require a changed deadline
or an existing schedule to cancel. Diagnostic observation does not own requests, retries, cache
freshness, location permissions or UI state.

`MainThreadWatchdog` records diagnostic breadcrumbs when the AppKit main thread remains unresponsive beyond its threshold and when responsiveness returns.

## Runtime verification support

Files:

- `Sources/CountdownManager/UISmokeControls.swift`
- `Sources/CountdownManager/UISmokeRuntime.swift`

These files provide in-process control and observation surfaces for Real UI Smoke when the dedicated test mode is active.

Event favorite/edit controls register and refresh through an invisible `NSViewRepresentable` lifecycle,
with coordinator-owned cleanup when their identity changes or their view is dismantled.
This avoids missing visible event buttons after SwiftUI reuses a compact row without another `onAppear`.
Other semantic controls retain SwiftUI registration, including offscreen checklist rows.
Geometry remains observed separately; scenarios wait for the required rendered layout rather
than assuming that a bound-value update and frame publication occur in the same pass.

Their capabilities, isolation model, and evidentiary limits are defined in `docs/VERIFICATION.md`.

## Verification targets

Swift Package verification targets include:

```text
CoreChecks
    → CountdownCore

UIChecks
    → CountdownCore + CountdownManagerUI
```

Real UI Smoke runs the production application runtime with isolated test state.

External XCUITest is maintained through the Xcode test project and runner.

Verification selection and command details belong in `docs/VERIFICATION.md`.


## Material intake

`MaterialDropZone` resolves NSItemProvider representations in file/image/web/text priority and cancels
late delivery when its target disappears. `EventMaterialTarget` binds the receiving event identity
and checks the shared editor gate before applying an asynchronous result. It shares the existing
Store/repository; there is no second persistence or clipboard-monitoring owner.

`MaterialImageImport` receives an advertised encoded image using `loadFileRepresentation` and
copies its short-lived file synchronously inside the provider callback. `StagedMaterialFile` owns
only its newly created temporary folder. `EventMaterials` carries that owner alongside the file URL;
Store and EditorAttachmentSession retain it through asynchronous import. Releasing the last owner
cleans staging on success, rejected delivery, cancellation or failure. The repository still owns all
durable attachment copies and their existing draft/commit cleanup. Provider Progress cancellation
is coordinated across cancellation before or after request installation. This is an image intake
boundary, not a general AppKit file-promise receiver.

Store owns pending quick additions and their admission locks. It imports into a temporary repository
draft, revalidates the current event and capacities after awaits, merges only new materials into the
latest event and commits through existing revision/recovery handling. There is no addition receipt,
result-message state or Undo API/view. Existing errors retain their established owner and presentation.
`TextAttachment` defines plain-text filename/content
validation; `AttachmentFiles` writes UTF-8 text using the same owned-folder/marker boundary as copies.

DesktopRootView reserves EventEditorSession and reuses DesktopSheet for a text composer. ManagerView
uses its existing internal navigation and the same editor-session reservation. EditorView retains its
own draft and EditorAttachmentSession under its nested composer, using that session's normal cleanup.
StatusItemMaterialDragView forwards ordinary mouse tracking to the original NSStatusBarButton and
reveals the existing panel during drag hover; it is not a file-import destination. Hover reveal orders
the panel without application activation, preserving the source application's drag.


The desktop Paste action follows AppKit's responder chain through its existing window controller.
The hosted root registers the current selected-event action while mounted. Native text responders
handle Paste first; the window controller only offers attachment composition for its key window
without a sheet. This avoids introducing a root-level SwiftUI paste hit target over a blocked
background. See Apple's [event architecture](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventArchitecture/EventArchitecture.html).


The panel's presentation request is owned by one `PanelPresentationState` in AppDelegate. A new
show remains pending until a visible occlusion observation is received; an earlier orderOut's
completion cannot cancel an unacknowledged show. After that acknowledgement, full occlusion keeps
its existing hide meaning. Explicit close/deactivation/Space/desktop-focus paths still hide
immediately. This does not attribute notifications to generations or use key/responder state,
window polling, timers, or hosting reconstruction. The native rapid hide→compact scenario remains
strict; its previous real disappearance is preserved separately from test-oracle failures.
