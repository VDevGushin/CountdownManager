# Countdown Manager — Verification Surfaces

This file is the project-specific map of available verification commands, what they can prove, and where they stop. Product acceptance methodology lives in `.agents/skills/product-qa/SKILL.md`.

Product behaviour is defined by `docs/PRODUCT.md`. Tests are evidence for that contract, not a replacement for it.

## Commands

| Surface | Command | Cost and scope |
| --- | --- | --- |
| SwiftLint | `swiftlint lint --config .swiftlint.yml --strict --no-cache` | Fast static checks over `Sources`, `Tests`, and `XCUITests` |
| CoreChecks + UIChecks | `./verify.sh fast` | Fast deterministic regression gate |
| Real UI Smoke | `./verify.sh ui` | Release build plus isolated in-process SwiftUI/AppKit runtime scenarios |
| Combined | `./verify.sh full` | `fast`, then Real UI Smoke |
| XCUITest | `./run-xcui-tests.sh` | External keyboard and normal button interaction through Xcode |

SwiftLint must be available on `PATH`; on macOS install it with `brew install swiftlint`.

Codex hooks run SwiftLint only on changed Swift files after an edit. Before a Swift task completes, they run full SwiftLint and `./verify.sh fast`. Real UI Smoke and XCUITest remain evidence selected for the actual runtime risk; they are not automatic gates for unrelated Swift work.

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

Current capabilities include:

- view construction and hosted root identity;
- panel/editor/list continuity across supported in-process hide/show paths;
- draft and scroll continuity;
- rendered control state;
- focus/responder paths reproducible in process;
- main-thread stall detection.

Limitations:

- it cannot prove that macOS delivered an external app switch, Space change, or status-item activation as a user would;
- test-mode lifecycle suppression or direct internal actions are not evidence of production system behaviour;
- configuration and property assertions support evidence but do not prove the corresponding user-visible interaction.

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
