# Countdown Manager — Verification

## Purpose

This document describes the verification surfaces that currently exist in Countdown Manager and how to choose evidence for a change.

Verification exists to answer a concrete question about changed behaviour.

Use the cheapest verification surface that can faithfully exercise the relevant failure mode.

Do not run every available suite by default.

## Source of truth

Product behaviour is defined by `docs/PRODUCT.md`.

Accepted durable technical decisions may further define implementation constraints within their scope.

Tests are evidence that an implementation satisfies a contract.

An existing test does not redefine product behaviour merely because it already exists.

If a test expectation conflicts with current product truth or an accepted decision, investigate the conflict rather than treating the test as automatically authoritative.

## Verification surfaces

Countdown Manager currently has four distinct verification surfaces:

```text
CoreChecks
UIChecks
Real UI Smoke
XCUITest
```

This is not a mandatory escalation sequence.

A change may require only one surface. Use a higher surface only when a lower one cannot faithfully exercise the relevant behaviour or failure mode.

## CoreChecks

Target: `CoreChecks`

Source: `Tests/CountdownCoreTests/`

Depends on: `CountdownCore`

CoreChecks exercises domain and persistence behaviour without launching the macOS application UI.

Current coverage includes behaviour such as:

- event validation;
- subtask validation and limits;
- calendar-day calculations;
- Today behaviour;
- event expiry;
- primary-event replacement;
- stable ordering;
- legacy and current JSON decoding;
- serialization round trips;
- persistence validation;
- persistence revision ordering;
- domain mutation behaviour.

Use CoreChecks when the changed contract can be proven entirely at the domain or repository level.

CoreChecks cannot prove SwiftUI rendering, AppKit lifecycle, real focus/responder behaviour, window interaction, event routing, or accessibility-driven external interaction.

## UIChecks

Target: `UIChecks`

Source: `Tests/CountdownManagerUITests/`

Depends on:

- `CountdownCore`;
- `CountdownManagerUI`.

Despite the source-directory name, UIChecks is not an external macOS UI automation suite.

It is an executable set of deterministic checks over presentation, application state, and selected persistence coordination.

Current coverage includes behaviour such as:

- user-facing terminology;
- date and countdown presentation;
- event ordering for presentation;
- menu-bar title generation;
- editor validation;
- editor draft behaviour;
- emoji selection behaviour;
- subtask grouping and progress;
- subtask domain state transitions;
- disclosure-state persistence;
- overlapping persistence outcomes.

Use UIChecks when the relevant behaviour lives in deterministic presentation or application-state logic and does not require proving real AppKit event routing.

## Real UI Smoke

Runner:

```sh
./verify.sh ui
```

Implementation support:

- `Sources/CountdownManager/UISmokeControls.swift`
- `Sources/CountdownManager/UISmokeRuntime.swift`

Real UI Smoke builds the current application and launches the actual SwiftUI/AppKit runtime in an isolated test environment.

The runner creates a temporary verification root and an ad-hoc signed application bundle.

The isolated configuration provides separate countdown data, `UserDefaults`, diagnostics, and result state and rejects a test home that overlaps production Application Support.

### Control registry

When smoke mode is active, selected SwiftUI views expose a deterministic in-process control registry to the smoke runtime.

The registry can provide actions, values, enabled state, view frames, and focus information.

### What Real UI Smoke can prove

Real UI Smoke is appropriate for behaviour that depends on the actual running SwiftUI/AppKit application, including selected:

- view construction;
- responder state;
- window runtime behaviour;
- editor lifecycle;
- repeated collapse/expand behaviour;
- window/root identity and session-continuity regressions;
- main-thread stall detection.

For window presentation, smoke may observe actual runtime state such as the effective style mask, standard-window-button objects, key eligibility, visibility, key status and `isOnActiveSpace`. Merely asserting that requested configuration properties were assigned is not evidence that the user-visible chrome or cross-Space interaction is correct.

### Boundary

An action invoked through the internal control registry is not equivalent to every possible external user action.

For example, directly invoking an internal close action can demonstrate runtime behaviour after closure but does not automatically prove that a real external click produces the correct close path.

Use external UI automation when the interaction itself is the contract being tested.

## Window-shell evidence classes

Window-shell changes require three clearly separated evidence classes.

### Deterministic UI/session harness

Real UI Smoke may isolate or suppress system lifecycle events. It proves retained window/hosting/root identity, scroll continuity, editor/draft continuity and Save/Cancel semantics. It is not evidence for production visibility, activation, deactivation, occlusion or Spaces behaviour.

### Production-shell XCU diagnostic

Run:

```sh
./verify.sh shell
```

This launches the Xcode-built application without `--xcui-testing`, so production activation, deactivation, Space, occlusion diagnostics and status-item lifecycle remain enabled. `HOME` and `CFFIXED_USER_HOME` point to a temporary test home for data isolation; they do not alter window lifecycle.

The current driver is diagnostic only. Its Finder-anchored coordinate click does not reliably deliver `status-action`, while a normal XCU status-item click activates Countdown Manager before delivering the click and changes the lifecycle under test. Therefore neither a pass nor a failure from this command is authoritative evidence for status-item activation or production window visibility.

The diagnostic attempts this sequence in ten fresh application processes:

1. fresh launch starts with the primary window hidden;
2. a status-item click makes the primary root visible and hittable;
3. Command-W makes the primary root absent through a supported product action;
4. a second status-item click makes it visible and hittable again in the same process.

Both status-item show operations use the existing external click attempt. One failed process makes the diagnostic command return failure. A failure reports the production lifecycle trace for status action, application activation, show, occlusion changes and `orderOut`. This may help distinguish action-delivery failure from later lifecycle behaviour, but it must not block the migration or be reported as behavioural proof.

For changes that also affect session continuity, separately run the deterministic editor/draft continuity scenario. Do not infer production visibility from that scenario.

### Manual system acceptance

Manual release acceptance is currently the authoritative shell evidence. It must cover:

1. fresh launch → status-item click → primary window opens;
2. hide through a supported product action → status-item click → the same window/session reopens;
3. main/list state → switch to another application → window hides;
4. editor with an unsaved draft → switch applications → window hides, then the same editor/draft survives reopening and input continues;
5. main/list state on Space A → Space B → return to Space A → the old window is hidden;
6. the same Space transition with an open editor and unsaved draft → the old window is hidden and the session survives;
7. status-item click on Space B → the user stays on Space B and the same retained window appears there.

These scenarios remain manual until a driver observably performs the real user interaction without changing the activation lifecycle itself. Configuration properties, callback registration and internal lifecycle calls are diagnostic evidence only.

### Shell acceptance condition

A build touching window lifecycle, status-item show/hide, activation/deactivation, occlusion, Spaces or window presentation cannot be accepted until its observable shell behaviour is proven. With the current driver limitations, that proof is manual. `./verify.sh shell` is neither a prerequisite for manual acceptance nor an acceptance result.

## XCUITest

Runner:

```sh
./run-xcui-tests.sh
```

Source: `XCUITests/CountdownManagerXCUITests.swift`

The runner uses `CountdownManager.xcodeproj`, the `CountdownManager` scheme, `xcodebuild test`, and temporary DerivedData.

Each XCUITest uses an isolated test home and fixture data rather than normal production state.

### What XCUITest can prove

XCUITest interacts with the running application through macOS accessibility/UI automation.

Use it when the changed behaviour depends on an externally delivered application interaction and the driver can perform that interaction without changing the contract under test.

Reliable examples in the current suite include:

- keyboard entry and focus transitions;
- real button interaction;
- Command-W hiding after the app is already active.

### Boundary

The current suite has two explicit modes. Ordinary tests pass `--xcui-testing`, which allows deterministic application-control testing while suppressing production system visibility triggers. The production-shell diagnostic omits that argument, but its status-item driver is not reliable enough to support a production visibility gate.

It does not automatically prove every possible system-wide interaction.

A contract involving an arbitrary outside click or another external system surface requires evidence that actually performs that interaction.

The current driver does not reliably automate application switching, switching macOS Spaces, returning to the original Space, or clicking the status item from the destination Space without changing activation itself. Those contracts remain manual acceptance requirements. Likewise, the absence of title-bar chrome in a release bundle requires visual inspection when automation cannot observe the rendered frame reliably.

Do not substitute an internal lifecycle call and describe it as equivalent external evidence.

## Commands

### Fast

```sh
./verify.sh fast
```

Runs:

- CoreChecks;
- UIChecks.

Use this when the relevant contracts are covered by deterministic domain, persistence, presentation, or application-state behaviour.

### Real UI

```sh
./verify.sh ui
```

Builds the current Swift package application in release mode, creates an isolated temporary application bundle, signs it ad hoc, and runs the current Real UI Smoke scenarios.

The current script includes the general smoke scenario, collapse regression, and repeated window/editor/list continuity runs.

Use this when the real SwiftUI/AppKit runtime is relevant.

### Production-shell diagnostic

```sh
./verify.sh shell
```

Builds the release configuration through Xcode and runs the existing ten-process production-shell diagnostic. Its exit status reports whether that diagnostic completed its attempted sequence; it does not accept or reject the product and is not a prerequisite for manual acceptance.

### Combined

```sh
./verify.sh full
```

Runs:

- CoreChecks;
- UIChecks;
- Real UI Smoke.

`full` does not run XCUITest.

Do not use `full` merely because it is available when a smaller verification surface is sufficient.

### XCUITest

```sh
./run-xcui-tests.sh
```

Builds and tests through the Xcode project with temporary DerivedData.

Use targeted XCUITest evidence when the changed contract depends on real external application interaction.

## Choosing evidence

Pure domain or repository behaviour, such as validation, date calculations, ordering, expiry, or JSON compatibility:

→ CoreChecks

Deterministic presentation or application state, such as menu-bar formatting, row grouping, editor validity, disclosure persistence, or persistence-state coordination:

→ UIChecks

Real SwiftUI/AppKit runtime behaviour, such as window/hosting identity, application integration, or session-continuity regressions:

→ Real UI Smoke

A contract whose failure mode is the actual external interaction itself:

→ XCUITest or another external driver capable of performing that interaction

Add lower-level checks when they provide useful focused regression coverage, not simply to duplicate the same assertion.

## Test isolation

Production Countdown Manager state must not be used as a mutation-test fixture.

Production event data normally lives at:

`~/Library/Application Support/CountdownManager/countdowns.json`

Real UI Smoke and XCUITest use explicit isolated test environments. The production-shell XCU test isolates its user home without passing the lifecycle-altering `--xcui-testing` argument.

A verification path that cannot establish safe isolation must not perform mutations against user data.

## Bundle provenance

Runtime evidence is meaningful only for the application build that was actually exercised.

`./verify.sh ui` builds the current Swift package source into a temporary application bundle immediately before the smoke run.

`./run-xcui-tests.sh` invokes `xcodebuild test` against the current Xcode project with temporary DerivedData.

When debugging or running a bundle manually, do not assume an existing `.app` corresponds to the current source tree.

If build provenance is unclear, treat the runtime result as insufficient evidence for the current source state.

## Temporary bundle versus installed application

The normal Real UI Smoke bundle and XCUITest application are test builds.

Neither automatically proves behaviour that specifically depends on the user's installed `/Applications/Countdown Manager.app`.

If installed location or installation state is itself relevant to the contract, that exact workflow requires separate evidence.

Installing or replacing the application in `/Applications` requires the approval defined in `AGENTS.md`.

## Existing tests and changed product behaviour

When product behaviour intentionally changes, existing regression tests may become obsolete.

Do not preserve an old assertion merely to keep the suite green.

Instead:

1. identify which product or technical contract the test was intended to protect;
2. compare it with the current source of truth;
3. retain, update, move, or remove the test according to the current contract.

A test that protects obsolete behaviour is not useful regression coverage.

## Failures

A failing check is evidence, not automatically proof of a production-code defect.

A failure may originate from product code, test code, stale expectations, the test environment, platform behaviour, or build configuration.

Classify the failure before changing production behaviour merely to satisfy the test.

## Verification scope

Verification should stop when sufficient evidence exists for the changed contract and relevant regression risk.

Expand verification when:

- a check fails;
- the implementation changes materially after a check;
- evidence exposes a new relevant risk;
- a lower-level test cannot faithfully exercise the failure mode.

Do not repeatedly run broader suites without a concrete reason.

## Reporting

Report material verification facts rather than a fixed status protocol.

Include, where relevant:

- command or targeted check performed;
- pass or failure;
- important behaviour not verified;
- environment limitation that prevented required evidence;
- remaining risk that affects confidence in the change.

No fixed `READY` template is required.
