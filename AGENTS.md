# Countdown Manager — Agent Bootstrap

Countdown Manager uses a repository-level agent harness.

## Start here

Before doing project work, read:

- `COUNTDOWN_MANAGER.md`

It is the canonical source for agent role, engineering policy, authority, product freeze, evidence, review behaviour, testing philosophy, user-data safety and context discipline.

Do not duplicate or reinterpret those rules here.

## Load context progressively

Understand the task before loading repository context.

Then load only what the task requires.

Do not automatically read:

- the entire repository;
- every skill;
- all documentation;
- historical investigation material;
- all tests.

More context is not automatically better context.

## Skills

If the task matches a repository skill, read that skill before executing the task.

Available repository procedures live under:

`/.agents/skills/`

Load only the relevant skill.

If no skill applies, work directly under `COUNTDOWN_MANAGER.md`.

## Reviews

`project-review` and `harness-review` are READ-ONLY by default.

A review produces findings and a recommended change set, then stops before implementation unless the Product Owner separately approves changes.

## Implementation tasks

An explicit implementation request such as “fix this bug” permits file changes within the agreed task scope.

Do not fix unrelated findings “while here”.

Commit, push, main-history changes, installation, release and destructive/data operations remain subject to the authority rules in `COUNTDOWN_MANAGER.md`.

## Platform-sensitive work

When architecture depends on macOS-specific SwiftUI/AppKit behaviour, use the `macos-platform-research` procedure as required by `COUNTDOWN_MANAGER.md`.

Do not guess platform behaviour when the implementation depends on it.

## Durable context

The repository is the system of record for durable product and engineering decisions.

Temporary investigation and execution detail should not become permanent context unless it represents a durable decision.

## Conflicts

`COUNTDOWN_MANAGER.md` is the canonical repository policy.

A skill must not override it.

If repository instructions conflict, stop and surface the conflict rather than silently choosing one.
