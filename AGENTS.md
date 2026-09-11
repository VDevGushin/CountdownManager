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

## Source-of-truth precedence

For user-visible behaviour, `docs/PRODUCT.md` is authoritative.

Accepted decisions define technical constraints and rationale within their scope but must not silently redefine product behaviour.

`docs/ARCHITECTURE.md` describes the current implementation; it is not a product contract.

Tests and current code are implementation evidence. If they conflict with current product truth or an accepted decision, surface the conflict instead of treating existing behaviour as automatically correct.

## Product Freeze

PRODUCT FREEZE is active until the Product Owner explicitly lifts it.

While active:

- do not add new features;
- do not perform optional product or UX improvements;
- do not silently change established user-visible semantics;
- bug fixes are allowed;
- data-safety work is allowed;
- verification work is allowed;
- harness maintenance is allowed.

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

Follow current Swift, SwiftUI, AppKit, and macOS platform conventions.

Prefer standard platform APIs and controls over custom lifecycle, interaction, or state-restoration machinery.

Keep types and views focused on one coherent responsibility. When code accumulates unrelated UI, state ownership, platform integration, diagnostics, or verification responsibilities, split it along those boundaries.

Prefer composable SwiftUI views when the split represents a real UI or state responsibility.

Do not introduce abstractions solely to reduce file size or line count.

## Verification

Choose verification according to the changed behaviour and failure mode using `docs/VERIFICATION.md`.

Use the cheapest reliable evidence that actually exercises the relevant contract.

Do not continue expanding verification after sufficient evidence is obtained unless a check fails, the implementation changes, or a new material risk appears.
