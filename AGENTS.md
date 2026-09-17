# Countdown Manager

Countdown Manager is a native macOS menu-bar application.

Keep repository context small and task-specific. Do not read every document, decision, skill, or test by default.

## Repository knowledge

Use the repository as the source of truth.

- User-visible product behaviour and invariants: `docs/PRODUCT.md`
- Current implementation structure and ownership: `docs/ARCHITECTURE.md`
- Verification commands, test surfaces, and evidence selection: `docs/VERIFICATION.md`
- Durable non-obvious technical decisions and rationale: `docs/decisions/`

Read only the sources relevant to the current task.

Before completing a change, check whether any repository source of truth has changed. Update only the document whose contract actually changed. Do not modify documentation merely for formal consistency.

## Source-of-truth precedence

For user-visible behaviour, `docs/PRODUCT.md` is authoritative.

Accepted decisions define technical constraints and rationale within their scope but must not silently redefine product behaviour.

`docs/ARCHITECTURE.md` describes the current implementation; it is not a product contract.

Tests and current code are implementation evidence. If they conflict with current product truth or an accepted decision, surface the conflict instead of treating existing behaviour as automatically correct.

## Scope

Work only within the requested scope.

Report materially relevant unrelated findings, but do not fix them unless they are explicitly added to scope.

## Product decisions

The Product Owner defines the desired user outcome, constraints, priorities, and genuinely unresolved product trade-offs.

The agent owns technical investigation and implementation.

Do not ask the Product Owner to choose implementation details such as Swift, SwiftUI, AppKit APIs, architecture, or test type.

Do not invent new product semantics when the repository already defines them.

If a task exposes a genuinely unresolved product decision that materially changes user behaviour, surface that specific decision.

## User data

Never use production Countdown Manager data as a mutation or destructive test fixture.

Do not migrate, reset, delete, or intentionally rewrite production user data without explicit Product Owner approval.

## Authority

An explicit implementation request authorizes repository file changes required for that scope.

Separate explicit approval is required for:

- commit;
- push;
- direct modification of `main` history or ref;
- merge, rebase, or cherry-pick into `main`;
- installing or replacing the application in `/Applications`;
- release or publication;
- production user-data migration or reset;
- destructive operations outside normal scoped implementation.

Approval for one action does not imply approval for another.

## macOS platform uncertainty

When the technical direction materially depends on uncertain SwiftUI, AppKit, or macOS behaviour, use:

`.agents/skills/macos-platform-research/SKILL.md`

Do not invoke platform research for ordinary domain or data logic.

## Code quality

For implementation and non-trivial code review, use:

`.agents/skills/swift-code-quality/SKILL.md`

Write code according to current Swift, SwiftUI, AppKit, and macOS best practices. Prefer current first-party platform guidance and documented APIs over folklore, historical workarounds, or custom infrastructure.

When API or platform semantics materially affect correctness, architecture, lifecycle, concurrency, accessibility, or user-visible behaviour, verify the assumption against current Apple or official Swift documentation. Use the macOS platform research skill when that uncertainty requires investigation rather than ordinary reference checking.

Prefer standard platform APIs and controls over custom lifecycle, interaction, state-restoration, or dependency machinery.

Keep types and views focused on one coherent responsibility. Split code along real ownership, state, UI, platform, side-effect, or verification boundaries rather than file size or line count.

Make state ownership and mutation authority clear. A piece of mutable state should have one coherent owner unless synchronization or replication is an explicit part of the design.

Keep side effects at explicit boundaries with a clear owner. Do not scatter persistence, notifications, timers, filesystem access, process interaction, window management, or other effects across unrelated views and models.

Make concurrency requirements explicit in the code. Use actor isolation and `@MainActor` where they are part of the contract; do not rely on incidental call-site behaviour for thread safety.

Do not introduce protocols, dependency containers, factories, wrappers, or other abstractions for hypothetical future flexibility. Add an abstraction when a real boundary, alternate implementation, substitution need, or independently meaningful contract exists now.

Prefer composable SwiftUI views when the split represents a real UI or state responsibility.

Do not introduce abstractions solely to reduce file size or line count.

## Verification

Choose verification according to the changed behaviour and failure mode using `docs/VERIFICATION.md`.

Use the cheapest reliable evidence that actually exercises the relevant contract.

Do not continue expanding verification after sufficient evidence is obtained unless a check fails, the implementation changes, or a new material risk appears.
