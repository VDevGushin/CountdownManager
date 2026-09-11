# Countdown Manager — Architecture

## Purpose

This document is a compact map of the current Countdown Manager implementation.

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

## Runtime overview

```text
NSApplication
    ↓
AppDelegate
    ↓
NSStatusItem + NSPopover
    ↓
ManagerView
    ↓
Store
    ↓
CountdownData
    ↓
CountdownRepository
    ↓
countdowns.json
```

`AppDelegate` owns the macOS application shell.

`ManagerView` and child views present state and route user actions to `Store`.

`Store` coordinates mutable application state, platform services, and asynchronous persistence.

`CountdownData` owns domain mutations and validation.

`CountdownRepository` owns serialized filesystem access.

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

`ManagerView` is the root SwiftUI view hosted inside the primary popover.

The SwiftUI layer owns transient presentation state such as:

- current event editor presentation;
- unsaved event-editor draft state;
- deletion confirmation;
- event and subtask action popovers;
- quick-subtask editor presentation and input.

User mutations are routed through `Store`.

## AppKit application shell

File: `Sources/CountdownManager/Application.swift`

`CountdownManagerApplication.run()` configures the shared `NSApplication` as an accessory application and runs it with an `AppDelegate`.

`AppDelegate` owns:

- `NSStatusItem`;
- the transient `NSPopover`;
- `Store`;
- menu-bar title synchronization;
- popover open and close behaviour;
- application activation;
- key-window and first-responder restoration;
- platform handling around the quick-subtask sheet;
- UI-smoke runtime startup when requested.

The popover content is hosted through `NSHostingController` with `ManagerView` as its root.

In the current implementation, `popoverDidClose` resets the transient session and assigns a new hosting controller. This is current implementation behaviour, not a product requirement.

User-visible popup semantics are defined by `docs/PRODUCT.md`.

Platform-specific lifecycle rationale is documented in:

`docs/decisions/popup-lifecycle.md`

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
