# Countdown Manager — Architecture

## Purpose

This document maps the current Countdown Manager implementation, including the anchored status-item panel shell.

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
- expiry and primary-event recovery;
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
- deterministic presentation logic;
- SwiftUI views and transient view state;
- UI preference state;
- diagnostics;
- runtime support for Real UI Smoke.

Key files:

- `Application.swift`
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
└── NSPanel (one strong reference, session lifetime, transient visibility)
    └── NSHostingController (one instance, stable root)
        └── ManagerView
            ├── retained list hierarchy
            └── one internal editing session and its draft
```

Create the panel and hosting hierarchy once. On every explicit show, calculate the panel origin from the current status-item button's screen rectangle, then activate and order that same panel front. Hide it with `orderOut` and route the close command through the same path. Do not assign a new hosting controller/root on hide, close, reopen or ordinary store updates.

SwiftUI view-value recomputation is normal and is not root reconstruction. Keep the list structurally alive while the editor is active; retaining only the hosting controller does not preserve a list removed by a conditional branch. A draft belongs to an explicit editing session, not to window visibility. Save success or Cancel ends that session; hiding does not.

Panel positioning and visibility are shell responsibilities. The borderless panel has no arrow, title bar or traffic-light controls; it is not movable, uses no ordering animation and moves to the active Space only during an explicit show. A synchronous requested-visible flag makes every status-item action resolve immediately: hide only when the panel is visibly presented on the active Space, otherwise show it there. When a requested-visible panel becomes fully occluded during a Space transition, its native occlusion callback clears that request and calls `orderOut`; application deactivation and `NSWorkspace.activeSpaceDidChangeNotification` use the same path as fallbacks. These signals are independent of list/editor state and first responder. Returning to an old Space cannot restore the panel; only a later status-item action can show and reposition it. There is no mouse monitor, responder teardown/restoration machine, persisted scroll offset, draft restoration or per-OS shell abstraction. Existing domain, persistence, disclosure preferences, date refresh, login integration and privacy-safe diagnostics retain their responsibilities.

## Runtime responsibilities

`AppDelegate` owns the status item, panel and hosting controller. `ManagerView` keeps the list mounted and conditionally presents one internal event editor. Hidden list content is disabled, excluded from hit testing and hidden from accessibility.

Views route mutations through `Store`. `Store` coordinates domain state and asynchronous persistence; `CountdownData` owns validation/mutations, and `CountdownRepository` owns serialized filesystem access.

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
- primary-event recovery;
- event save and validation;
- event deletion;
- subtask CRUD and completion toggling.

It also stores `primaryID`.

## Persistence boundary

File: `Sources/CountdownCore/CountdownRepository.swift`

`CountdownRepository` is an actor that serializes production filesystem reads and writes outside the main UI actor.

It decodes and atomically writes `CountdownData` and rejects an older revision when a newer revision has already been accepted by the repository.

Persistence rationale and revision guarantees are documented in:

`docs/decisions/persistence-and-user-data.md`

## Application state

File: `Sources/CountdownManager/Store.swift`

`Store` is a `@MainActor` `ObservableObject` and is the primary application-state coordinator between UI, domain model, platform services, and persistence.

It owns or exposes:

- current `CountdownData`;
- current calendar day;
- loading and error state;
- launch-at-login status;
- active event ordering;
- current primary event;
- menu-bar title;
- subtask disclosure state.

`Store` also coordinates application-state revisions and durable snapshots around asynchronous repository writes.

Date-sensitive state is refreshed from timers and relevant macOS lifecycle, clock, time-zone, calendar-day, and wake notifications.

Launch at login is integrated through `SMAppService.mainApp`.

## UI preference state

Files:

- `Sources/CountdownManager/Presentation.swift`
- `Sources/CountdownManager/Store.swift`

Subtask disclosure state is separate from `CountdownData`.

`SubtaskDisclosurePersistence` stores per-event values in `UserDefaults` and `SubtaskDisclosureCache` supplies observable per-event state to the SwiftUI layer.

## Presentation layer

File: `Sources/CountdownManager/Presentation.swift`

Contains deterministic UI-facing transformations and state that do not require SwiftUI view construction, including:

- user-facing strings;
- compact emoji presets;
- row presentation values;
- human-readable dates;
- active-event ordering for presentation;
- menu-bar title generation;
- editor validity checks;
- editor draft representation;
- disclosure preference persistence.

## SwiftUI views

File: `Sources/CountdownManager/Views.swift`

`ManagerView` is the stable root inside the retained hosting controller. It owns the current internal editor presentation; `EditorView` owns its draft, date, primary selection and inline deletion confirmation. Save success or Cancel ends editing; hiding the panel does not. An unavailable event retains its draft and cannot be saved as that event.

Emoji selection stays in the editor through a plain current-value display, compact presets and an inline expanded catalog. `Ещё…` reveals a fixed-size paged grid: `EditorView` keeps a transient page index, renders three six-row/eight-column pages from the existing catalog, slides the page strip horizontally, and exposes previous/next buttons plus clickable page dots. A horizontal drag changes the transient page index as well. The first page reuses the compact presets as its top row. Choosing an emoji replaces the draft value, resets the page index and collapses the expanded grid; the transitions respect Reduce Motion. Emoji selection does not use an editable text field, first-responder handoff or an application-owned popover. Subtask text changes use the same editor; primary selection and completion remain in the list. Errors are presented inline. No editor sheets or application-owned action/emoji popovers remain.

## AppKit application shell

File: `Sources/CountdownManager/Application.swift`

`CountdownManagerApplication.run()` configures `NSApplication` as an accessory application. `AppDelegate` creates one status item, one borderless key-capable `NSPanel` and one hosting controller at startup. It retains all three through the session, starts the Store/diagnostics and supplies isolated test configuration when requested.

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
