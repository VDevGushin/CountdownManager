# Countdown Manager — Architecture

## Purpose

This document maps the current Countdown Manager implementation, including the anchored status-item panel shell and the single countdown timer.

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

### `CountdownManagerUI`

Source: `Sources/CountdownManager/`

Owns the running macOS application behaviour.

Key responsibilities:

- AppKit application and menu-bar integration;
- application state and persistence coordination;
- the single timer, its local preference state, ticking and completion presentation;
- session-only prevention of idle system/display sleep;
- deterministic presentation logic;
- SwiftUI views and transient view state;
- UI preference state;
- diagnostics;
- runtime support for Real UI Smoke.

Key files:

- `Application.swift`
- `CountdownTimer.swift`
- `KeepAwakeController.swift`
- `ApplicationUpdates.swift`
- `TimerCompletionAlert.swift`
- `Store.swift`
- `Presentation.swift`
- `Views.swift`
- `Diagnostics.swift`
- `UISmokeControls.swift`
- `UISmokeRuntime.swift`

### `CountdownManager`

Source: `Sources/CountdownManagerApp/`

Owns the executable entry point.

`App.swift` delegates application startup to `CountdownManagerApplication.run()`.

## Shell implementation status

The implementation uses one borderless `NSPanel` anchored to the status item and one long-lived `NSHostingController`, both owned for the application session. See [the accepted shell decision](decisions/status-item-panel-shell.md).

### Ownership

```text
NSApplication / AppDelegate
├── NSStatusItem
├── Store → CountdownData / CountdownRepository → countdowns.json
├── CountdownTimer → UserDefaults
├── KeepAwakeController → one process-owned IOPM assertion
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

Views route event mutations through `Store`. `Store` coordinates domain state and asynchronous event persistence; `CountdownData` owns validation/mutations, and `CountdownRepository` owns serialized filesystem access.

Timer mutations route through `CountdownTimer`. It stores one absolute deadline in `UserDefaults`, derives remaining time from the current clock, publishes second-level UI updates only while a deadline exists, and emits a one-shot completion event when a running deadline is crossed. It never writes timer ticks into event persistence and schedules no system notifications.

## Domain model

File: `Sources/CountdownCore/Countdown.swift`

### `Day`

Represents a civil Gregorian date as year, month, and day rather than an absolute timestamp.

### `Countdown`

Persisted event model containing stable identity, title, optional note, date, emoji, and subtasks.

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

It stores the optional explicit favorite in `primaryID`. Normalization clears an expired or invalid selection; it does not populate an absent selection. An empty `emoji` string represents no additional icon, preserving the existing JSON field shape.

The timer deliberately does not belong to `CountdownData`: events use civil-day semantics, while the timer uses an absolute deadline.

## Persistence boundary

File: `Sources/CountdownCore/CountdownRepository.swift`

`CountdownRepository` is an actor that serializes production filesystem reads and writes outside the main UI actor.

It decodes and atomically writes `CountdownData` and rejects an older revision when a newer revision has already been accepted by the repository.

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

Date-sensitive event state is refreshed from timers and relevant macOS lifecycle, clock, time-zone, calendar-day, and wake notifications.

Launch at login is integrated through `SMAppService.mainApp`. Settings binds to the existing
`Store.loginStatus` and actions, including the `requiresApproval` System Settings route; it does
not maintain another login preference.

## Keep-awake state

File: `Sources/CountdownManager/KeepAwake.swift`

`KeepAwakeController` is the single `@MainActor` owner of the session's sleep-prevention state
and IOPM assertion identifier. `AppDelegate` creates it once and supplies it to the retained UI.
Settings reads its accepted state and requests enable/disable; view rendering and panel visibility
do not acquire or release assertions. Neither event persistence nor `UserDefaults` stores this
mode, so a new process always begins disabled.

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
release the assertion; cancelling an update termination retains the running session and its
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
hide boundary and returns to the retained panel through an explicit button; it never retries itself.

`AppDelegate` owns `EventEditorSession`, the single observable owner of editor visibility shared
with `ManagerView`. Draft fields remain owned by the existing editor. The updater reads that session,
the timer phase and `Store.hasPendingPersistence` through an explicit main-actor safety closure.
It stores Sparkle's native postponement continuation while blocked. Explicit Install rechecks
safety before consuming the continuation once. `willInstallUpdate` marks update termination;
`applicationShouldTerminate` cancels it if activity appears in the remaining installation window.
Explicit application Quit clears that update-specific flag before its normal termination request.

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

## Presentation layer

File: `Sources/CountdownManager/Presentation.swift`

Contains deterministic UI-facing transformations and state that do not require SwiftUI view construction, including:

- user-facing strings;
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

`CountdownManagerRootView` is the stable SwiftUI root inside the retained hosting controller. It composes the compact timer strip with `ManagerView`.

`AuroraInstrument` supplies the shared warm light/dark palette, contrast variants and control backgrounds. Event rows compose a larger right-hand calendar leaf for the displayed favorite or automatic nearest event and a smaller left-hand leaf for other events. `Store.primary` derives the displayed event without changing the explicit selection. `CountdownRowPresentation` separates `isFeatured` (large presentation) from `isPrimary` (filled star). Menu-bar emoji fallback is `📅`; calendar labels and optional list emoji are derived from `Presentation.swift`; they introduce no separate event state or persisted representation.

An event surface groups the row and its checklist as one block. Checklist disclosure continues to use the cached `SubtaskDisclosureState` as its sole owner; standard SwiftUI layout and opacity transitions animate its presentation without storing a second expanded state or introducing timer-based animation control.

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
Settings groups the existing login and Sparkle automatic-check bindings with the session keep-awake
checkbox, then manual update and diagnostics actions. A deferred update replaces the manual-check
action with the existing explicit install entry point. Login approval and operation errors remain
visible. There is no settings draft or Save/Cancel; accepted owner state is shown immediately.
The timer strip stays outside this screen navigation at the top of the same 390 × 600 panel.

The header calendar control reveals inline `Сегодня`, `Завтра` and `Выбрать дату` day creation choices; the existing `+` still opens ordinary event creation directly. Day creation supplies transient editor defaults rather than a new persisted event type: today's date for `Сегодня`, tomorrow's date for the other routes, no additional emoji, a Russian weekday title and empty note/subtasks. Ordinary event creation also initially selects tomorrow. The date field allows today and future dates; selecting today reveals an inline explanation of end-of-day expiry, including unfinished subtasks. The choose-date route uses the same editor date field with an explanatory hint. During a new-day draft, date changes regenerate the weekday title until the first manual title edit; existing-event editing never regenerates a stored title. Creation actions preserve an already open editor, and the underlying list stays mounted. Save uses the unchanged Store and `Countdown` persistence boundary, checking against the current calendar day at the mutation boundary; no template library, week state or schema field is introduced.

The editor groups event fields, additional emoji and subtasks on separate subtle surfaces, followed by the favorite choice. The scrollable form keeps the existing retained draft and fixed action footer. Emoji selection uses a full-width button styled as a selection field, with a disclosure chevron and a separate clear button inside the same visual boundary. Empty selection hides the clear button rather than reserving a disconnected action area.

Editor subtask rows use identity-scoped layout/opacity animation for Add/Delete. Their text bindings
resolve stable UUIDs against the same parent draft and retain an immutable outgoing value while a
removed row finishes its transition; setters ignore absent UUIDs. Removed rows lose input and
accessibility eligibility immediately. Deferred Add focus checks membership before scrolling or
focusing. Typing does not change the identity array and therefore does not animate the block.

`EditorView` owns one transient picker state: closed, compact presets or a catalog page. The selector starts closed; `Все значки` advances from compact presets to the inline catalog. The catalog retains five named six-row/eight-column sets (`Общие`, `Дети`, `Работа`, `Транспорт`, `Праздники`), conventional previous/next controls, page dots and horizontal drag navigation. Grid dimensions fit the grouped editor's inner width. Choosing or clearing an emoji replaces only the draft value and closes the picker, resetting navigation. Native layout/opacity transitions animate disclosure for 200 milliseconds while page changes slide horizontally; both respect live Reduce Motion. The stable picker boundary excludes closed content from hit testing and accessibility, including during removal transitions. Emoji selection does not use an editable text field, first-responder handoff or an application-owned popover. Subtask text changes use the same editor; primary selection and completion remain in the list. Errors are presented inline. No editor sheets or application-owned action/emoji popovers remain.

## AppKit application shell

File: `Sources/CountdownManager/Application.swift`

`CountdownManagerApplication.run()` configures `NSApplication` as an accessory application.
`AppDelegate` creates one status item, one borderless key-capable `NSPanel`, one `Store`, one
`CountdownTimer`, one `KeepAwakeController` and one hosting controller at startup. It retains them
through the session, starts diagnostics and supplies isolated test defaults/data when requested.

`AppDelegate` merges Store and timer change notifications to update the status item. A running or finished timer temporarily overrides the normal event status title and shows the `alarm.fill` SF Symbol next to the remaining time; the finished state shows the symbol alone. While the timer runs, the status item breathes with a gentle repeating opacity pulse. The finished alarm receives a repeating Core Animation rock — each tilt pivots on its own bottom corner with a tiny lift, so it hops from foot to foot — until deletion, or an opacity pulse when Reduce Motion is enabled. It subscribes to the timer's one-shot completion event so the five-second application-owned alert and sound are presented while the accessory app is active.

Status-item actions toggle the requested visibility state immediately. Show orders out any stale visible instance, positions the panel under the current status item, activates the accessory app and makes the panel key/front. Hide, full occlusion while requested visible, application deactivation, active-Space change and Command-W clear requested visibility and call `orderOut`. Ordinary startup does not open it. Isolated harnesses suppress these automatic lifecycle callbacks while verifying retained panel/hosting/root/list/editor state; observable anchoring, app-switch, Space and real status-item interaction remain release manual acceptance.

A standard AppKit application menu supplies text-editing commands, Quit and the native close command. The panel's native occlusion callback closes a visually departed panel even when a rapid Space transition is reversed before the workspace posts its completed-change notification. There is no window centering, movement, frame persistence, mouse monitor, workspace polling, key/responder-driven visibility hook, sheet-end observer, forced first-responder assignment or root reconstruction.

Product semantics live in `PRODUCT.md`; accepted rationale lives in `decisions/status-item-panel-shell.md`. The superseded standalone-window, popover and historical popup decisions retain prior evidence only.

## Diagnostics

File: `Sources/CountdownManager/Diagnostics.swift`

`DiagnosticLog` writes privacy-limited technical diagnostics to Unified Logging and a local rotating file journal on a dedicated utility queue.

`MainThreadWatchdog` records diagnostic breadcrumbs when the AppKit main thread remains unresponsive beyond its threshold and when responsiveness returns.

## Runtime verification support

Files:

- `Sources/CountdownManager/UISmokeControls.swift`
- `Sources/CountdownManager/UISmokeRuntime.swift`

These files provide in-process control and observation surfaces for Real UI Smoke when the dedicated test mode is active.

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
