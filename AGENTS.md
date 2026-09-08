# Countdown Manager — Agent Bootstrap

Countdown Manager uses a repository-level agent harness.

## Start here

Before doing project work, read:

- `COUNTDOWN_MANAGER.md`

It is the canonical source for agent role, engineering policy, authority, product freeze, evidence, review behaviour, test philosophy, user-data safety and context discipline.

Do not duplicate or reinterpret those rules here.

## Route the task

Classify the request before loading broader repository context.

If the task matches a repository procedure, load only that skill:

- project health / engineering review → `.agents/skills/project-review/SKILL.md`
- harness review / harness freshness → `.agents/skills/harness-review/SKILL.md`
- macOS-specific SwiftUI/AppKit behaviour that affects architecture → `.agents/skills/macos-platform-research/SKILL.md`

If no skill applies, work directly under `COUNTDOWN_MANAGER.md`.

All permissions, approval boundaries and review semantics are canonical in `COUNTDOWN_MANAGER.md`; do not restate them here.

## Load context progressively

Understand the task before loading repository context.

Then read only what the task requires.

Do not automatically read:

- the entire repository;
- every skill;
- all documentation;
- historical investigation material;
- all tests.

More context is not automatically better context.

## Repository map

Use these sources only when relevant:

- `README.md` — current product behaviour and user/developer documentation;
- `VERIFICATION.md` — current verification layers, commands and operational boundaries;
- `docs/decisions/` — durable architectural decisions and their evidence;
- temporary plans/investigations — execution context, not permanent policy.

## Conflicts

`COUNTDOWN_MANAGER.md` is the canonical repository policy.

A skill or supporting document must not override it.

If repository instructions conflict, stop and surface the conflict rather than silently choosing one.
