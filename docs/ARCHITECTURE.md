# Countdown Manager — Architecture

## Purpose

This document maps the current Countdown Manager implementation, including the long-lived window shell.

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

The working implementation uses one long-lived utility-styled `NSWindow` with one `NSHostingController`, owned for the application session. See [the accepted shell decision](decisions/window-shell.md). Runtime verification results and remaining gaps are recorded in [the migration scope](plans/window-shell-migration.md).

### Ownership

```text
NSApplication / AppDelegate
├── NSStatusItem
├── Store → CountdownData / CountdownRepository → countdowns.json
└── NSWindow (one strong reference, session lifetime)
    └── NSHostingController (one instance, stable root)
        └── ManagerView
            ├── retained list hierarchy
            └── one internal editing session and its draft
```

Create the window and hosting hierarchy once, eagerly or on first use. Hide through `orderOut`; show and activate the same window through ordinary AppKit window APIs. Keep `isReleasedWhenClosed = false` and route the close command through the same hide path. Do not assign a new hosting controller/root on hide, close, reopen or ordinary store updates.

SwiftUI view-value recomputation is normal and is not root reconstruction. Keep the list structurally alive while the editor is active; retaining only the hosting controller does not preserve a list removed by a conditional branch. A draft belongs to an explicit editing session, not to window visibility. Save success or Cancel ends that session; hiding does not.

Normal window activation and visibility are shell responsibilities. The retained `CountdownUtilityWindow` uses the borderless style mask and overrides `canBecomeKey` and `canBecomeMain` so SwiftUI controls keep normal focus and editing. The application delegate hides the retained window on application deactivation, and an `NSWorkspace.activeSpaceDidChangeNotification` observer hides it on a Space change. Both signals live above SwiftUI content and do not depend on list/editor state, key-window state or first responder. Native `hidesOnDeactivate` is disabled because it can hide a window while the status-item Show action is still activating it. It opts into `moveToActiveSpace`; if a visible instance belongs to another Space, the show path orders it out before application activation and then makes the same instance key and front. There is no responder teardown/restoration machine, mouse monitor, popup introspection, persisted scroll offset, draft restoration or per-OS shell abstraction. Existing domain, persistence, disclosure preferences, date refresh, login integration and privacy-safe diagnostics retain their responsibilities.

The bounded implementation work is specified in [the production migration scope](plans/window-shell-migration.md).

## Runtime responsibilities

`AppDelegate` owns the status item, window and hosting controller. `ManagerView` keeps the list mounted and conditionally presents one internal event editor. Hidden list content is disabled, excluded from hit testing and hidden from accessibility.

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
- emoji catalog;
- row presentation values;
- human-readable dates;
- active-event ordering for presentation;
- menu-bar title generation;
- editor validity checks;
- editor draft representation;
- disclosure preference persistence.

## SwiftUI views

File: `Sources/CountdownManager/Views.swift`

`ManagerView` is the stable root inside the window. It owns the current internal editor presentation; `EditorView` owns its draft, date, primary selection and inline deletion confirmation. Save success or Cancel ends editing; hiding the window does not. An unavailable event retains its draft and cannot be saved as that event.

Emoji selection is embedded in the editor. Subtask text changes use the same editor; primary selection and completion remain in the list. Errors are presented inline. No editor sheets or action/emoji popovers remain.

## AppKit application shell

File: `Sources/CountdownManager/Application.swift`

`CountdownManagerApplication.run()` configures `NSApplication` as an accessory application. `AppDelegate` creates one status item, one borderless `CountdownUtilityWindow` and one hosting controller at startup. It retains them through the session, starts the Store/diagnostics and supplies isolated test configuration when requested. The window's key/main overrides preserve keyboard focus without adding title-bar chrome.

Status-item actions hide a visible window or activate/show the existing hidden window. Explicit Show remains in progress until AppKit reports the application active and the retained window key, so deactivation and Space callbacks cannot cancel that same presentation. Later application deactivation or active-Space change routes through `orderOut`. A visible instance on another Space is ordered out before application activation; `moveToActiveSpace` then applies when that same instance is made key and front on the active Space. Command-W also routes directly to `orderOut`; release-on-close is disabled. Ordinary startup does not open it. Isolated harnesses suppress the deactivation and Space callbacks while verifying retained identity/state; observable auto-hide remains release manual acceptance.

A standard AppKit application menu supplies text-editing commands, Quit and the native close command. Application activation callbacks and the native active-Space notification own visibility; occlusion changes are diagnostics rather than behavioural proof. There are no mouse monitors, workspace polling, key/responder-driven visibility hooks, sheet-end observers, deferred reopen flags, forced first-responder assignments or root reconstruction.

Product semantics live in `PRODUCT.md`, accepted rationale in `decisions/window-shell.md`, and the superseded popup decision retains historical evidence only.

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
