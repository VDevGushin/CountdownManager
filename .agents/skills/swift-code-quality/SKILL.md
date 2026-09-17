---
name: swift-code-quality
description: Write and review Countdown Manager Swift, SwiftUI, and AppKit code using current platform best practices, explicit ownership, simple architecture, and testable boundaries.
---

# Swift Code Quality

## Purpose

Use this skill for implementation and non-trivial code review in Countdown Manager.

The goal is production-quality Swift that is clear, idiomatic, maintainable, platform-correct, and no more abstract than the current problem requires.

Prefer the simplest design that preserves the product contract, makes ownership obvious, respects platform semantics, and can be verified reliably.

## Sources of truth

Use repository contracts first:

- product behaviour: `docs/PRODUCT.md`;
- current implementation structure: `docs/ARCHITECTURE.md`;
- verification strategy: `docs/VERIFICATION.md`;
- accepted technical constraints: `docs/decisions/`.

For Swift, SwiftUI, AppKit, Foundation, accessibility, lifecycle, concurrency, or other platform behaviour, prefer current first-party sources:

1. Apple documentation;
2. Apple Human Interface Guidelines when interaction semantics matter;
3. Apple release notes and framework documentation;
4. official Swift documentation and Swift Evolution proposals;
5. direct observation on the supported runtime when documentation is insufficient.

Do not prefer blog patterns, historical Stack Overflow workarounds, copied architecture templates, or community folklore over current first-party guidance.

Do not perform broad platform research for ordinary code. When a material technical decision depends on uncertain macOS, SwiftUI, or AppKit behaviour, use `.agents/skills/macos-platform-research/SKILL.md`.

## 1 — Start from the contract

Before changing code, identify:

- the behaviour being added, preserved, or corrected;
- the current owner of that behaviour;
- the smallest implementation boundary that should change;
- the failure mode that must remain verifiable.

Do not redesign adjacent code merely because it can be improved.

Do not invent product semantics to make an implementation convenient.

## 2 — Prefer native, direct solutions

Use current Swift language features and standard Apple APIs when they express the required behaviour clearly.

Prefer:

- value semantics where identity is unnecessary;
- structured concurrency over callback or queue machinery when appropriate;
- SwiftUI state and composition mechanisms where they fit naturally;
- AppKit only where AppKit ownership or behaviour is genuinely required;
- Foundation types and platform services over custom replacements.

Avoid custom lifecycle, observation, state-restoration, scheduling, event-routing, or dependency machinery when the platform already provides a suitable mechanism.

A platform API is not automatically correct merely because it exists. Verify semantics when correctness depends on lifecycle, focus, activation, persistence, concurrency, accessibility, or window behaviour.

## 3 — Make ownership obvious

Every important piece of mutable state should have one coherent owner.

The owner is the component responsible for the state's lifetime and authoritative mutation.

Do not keep independent mutable copies of the same conceptual state in a view, model, controller, coordinator, or service unless synchronization or replication is explicitly required by the design.

Derived state should usually be derived rather than stored separately.

Pass data downward and actions or bindings toward the owner instead of creating hidden secondary ownership.

When ownership is unclear, fix ownership before adding synchronization code.

## 4 — Keep side effects at explicit boundaries

Treat these as side effects unless the surrounding abstraction already owns them:

- persistence;
- filesystem access;
- process launching or shell interaction;
- timers;
- notifications and observers;
- status-item, window, popover, or panel control;
- clipboard and system services;
- network or external-service access;
- logging that affects diagnostics or persisted evidence.

A side effect should have a clear owner and lifecycle.

Do not trigger significant effects from arbitrary view rendering, computed properties, convenience getters, or unrelated model mutations.

Keep pure transformation and decision logic separate from effect execution when doing so makes behaviour clearer or easier to verify.

Do not introduce an effect abstraction solely to make code look layered.

## 5 — Use Swift concurrency deliberately

Concurrency is part of correctness, not an implementation afterthought.

Make isolation explicit when it is part of the contract:

- use `@MainActor` for UI-owned state and APIs that require main-actor isolation;
- use actors when mutable state truly requires isolated concurrent access;
- preserve structured task lifetimes where possible;
- propagate cancellation when the operation should stop with its caller or owner;
- avoid detached tasks unless detachment is intentionally required;
- do not use `Task { @MainActor in ... }` as a generic patch for unclear ownership or isolation;
- do not rely on incidental callers always arriving on the main thread.

Avoid unnecessary concurrency. Synchronous code is preferable when work is cheap, ordered, and does not benefit from asynchronous execution.

Do not add locks, queues, actors, or tasks without a concrete concurrency requirement.

## 6 — Keep SwiftUI state local and intentional

Use SwiftUI as a declarative UI system rather than recreating imperative view-controller state management inside it.

Choose state storage according to ownership and lifetime, not convenience.

A view should not own long-lived application state merely because `@State` makes mutation easy.

Prefer bindings when a child edits state owned by its parent or another clear owner.

Keep transient presentation state close to the presentation that owns it.

Extract a SwiftUI view when it has a meaningful visual, state, lifecycle, or interaction responsibility. Do not extract views solely to reduce line count.

Avoid hidden work in `body`. Rendering should primarily describe UI from state.

Do not create view models mechanically for every view. Introduce a separate model or controller when it owns meaningful state, effects, lifecycle, or domain behaviour that should not belong to the view.

## 7 — Keep AppKit boundaries narrow

Use AppKit where Countdown Manager needs AppKit-specific lifecycle, windowing, responder, status-item, accessibility, or interoperability behaviour.

Keep platform-specific ownership close to the object that actually controls that platform resource.

Do not leak `NSWindow`, `NSPopover`, responder-chain mechanics, or application lifecycle concerns through unrelated domain and persistence code.

When bridging SwiftUI and AppKit, make it clear which side owns:

- the hosted hierarchy;
- presentation lifetime;
- visibility;
- focus or first responder;
- callbacks and cleanup.

Do not compensate for uncertain platform behaviour with complex custom machinery before verifying the platform semantics.

## 8 — Add abstractions only for real boundaries

Do not introduce protocols, factories, dependency containers, service locators, wrappers, coordinators, repositories, managers, or generic helpers because they might become useful later.

An abstraction is justified when at least one current need exists, such as:

- multiple real implementations;
- substitution at a meaningful test or runtime boundary;
- a stable contract independent of a concrete implementation;
- separation of platform-specific behaviour from domain behaviour;
- ownership or lifecycle that deserves an independent component;
- repeated behaviour whose shared semantics are real and stable.

A protocol with one implementation is not automatically wrong, but its boundary must have a current purpose.

Do not add dependency injection frameworks for a small dependency graph. Prefer explicit initializer or parameter injection when substitution is actually useful.

Do not create wrappers that merely rename an Apple or Swift API without adding a meaningful contract.

## 9 — Keep types cohesive

A type should have one coherent reason to change.

Split a type when it accumulates unrelated responsibilities such as:

- domain rules plus window management;
- persistence plus presentation formatting;
- view rendering plus platform lifecycle control;
- state ownership plus unrelated diagnostics;
- multiple independent effects with different lifetimes.

Do not split types solely because a file is long.

Do not merge responsibilities merely because they share data.

Prefer small private helpers for local readability before inventing new architectural layers.

## 10 — Design APIs for clarity

Prefer names that communicate domain meaning and effect.

Make mutation visible in API shape and naming.

Prefer narrow access control. Keep implementation details `private` or internal unless another component genuinely needs them.

Avoid boolean parameters when the call site becomes ambiguous; use a small enum or clearer operation when distinct semantics exist.

Avoid broad utility types containing unrelated static helpers.

Avoid clever generic code when concrete code is clearer and duplication is small.

Do not expose mutable collections or implementation objects when callers only need a narrower operation or read-only value.

## 11 — Handle errors at the right boundary

Do not silently swallow errors that affect correctness, user data, or user-visible behaviour.

Do not propagate low-level errors through every layer when the caller cannot act on that detail.

Translate errors at the boundary where their meaning changes.

Use `Result`, throwing APIs, optional values, or explicit state according to semantics rather than stylistic preference.

Do not use `try?` merely to make an error disappear.

Do not use `fatalError`, forced casts, or forced unwraps for recoverable runtime conditions.

Forced unwraps are acceptable only when the invariant is local, obvious, and genuinely impossible to violate in supported execution; prefer expressing the invariant structurally when practical.

## 12 — Preserve data and compatibility deliberately

Treat persisted Countdown Manager data as a compatibility contract.

Do not change encoding, decoding, defaults, migration behaviour, identifiers, ordering semantics, or revision handling accidentally during refactoring.

When changing a persisted representation, understand backward and forward compatibility implications before implementation.

Never use production user data as a destructive or mutating test fixture.

## 13 — Optimize only with evidence

Prefer clear code before speculative optimization.

Do not cache, memoize, batch, debounce, parallelize, or introduce custom data structures without a concrete need.

When performance matters, identify the actual expensive path and preserve correctness first.

For UI work, avoid unnecessary work in render paths, repeated expensive computation, avoidable object reconstruction, or uncontrolled task creation.

## 14 — Comments explain why

Prefer code that explains what it does through naming and structure.

Use comments for:

- non-obvious invariants;
- platform constraints;
- compatibility requirements;
- intentional trade-offs;
- reasons a simpler-looking approach is incorrect.

Do not narrate obvious code.

Remove stale comments when the implementation changes.

Durable non-obvious architectural rationale belongs in `docs/decisions/` when it is important beyond the local code.

## 15 — Keep code testable without coding for tests

Structure code so important behaviour can be exercised at the cheapest reliable verification surface.

Prefer testing observable contracts and meaningful state transitions over private implementation shape.

Do not expose internals, add production switches, introduce unnecessary protocols, or alter lifecycle behaviour merely to satisfy a test harness.

When a bug can be represented reliably below a system-interaction boundary, add or update focused regression coverage at that level.

When automation cannot faithfully reproduce the real interaction, follow `docs/VERIFICATION.md` rather than distorting production code for automation.

## 16 — Review the diff, not just the result

Before completing implementation, inspect the change as a whole.

Check for:

- duplicated ownership;
- accidental new state;
- hidden side effects;
- unnecessary abstractions;
- incorrect actor or main-thread assumptions;
- platform APIs used against documented semantics;
- retain cycles or observer/task lifetime leaks;
- accidental persistence-format changes;
- unrelated cleanup outside scope;
- tests coupled to implementation details;
- comments or documentation made stale by the change.

Prefer deleting accidental complexity over documenting it.

## Completion standard

A coding change is ready for verification when:

- it implements the repository contract without inventing new product semantics;
- ownership and mutation authority are clear;
- side effects and lifetimes have clear owners;
- concurrency assumptions are explicit and justified;
- platform-sensitive behaviour follows current first-party guidance or has been investigated;
- abstractions exist only for current, meaningful boundaries;
- the diff contains no unrelated architectural cleanup;
- relevant persisted-data compatibility has been considered;
- the changed failure mode can be verified using `docs/VERIFICATION.md`.

Then run only the verification required by the changed behaviour and failure mode.
