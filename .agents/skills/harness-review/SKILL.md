---
name: harness-review
description: Read-only review of the Countdown Manager agent harness for correctness, freshness, duplication, cost and maintainability.
---

# Harness Review

## Purpose

Evaluate whether the Countdown Manager agent harness still improves engineering behaviour without accumulating unnecessary complexity.

This skill is READ-ONLY by default.

Do not change the harness during the review.

## Scope

Inspect:

- `AGENTS.md`;
- `COUNTDOWN_MANAGER.md`;
- repository skills;
- durable context architecture;
- authority boundaries;
- evidence rules;
- review behaviour;
- test-policy interaction;
- documentation duplication;
- token/runtime/human cost;
- tooling assumptions;
- stale workarounds;
- current relevant agent-engineering practices.

Use progressive disclosure.

Do not review the entire application codebase unless a harness question requires evidence from it.

## Freshness

Check external practices only when useful to determine whether the current harness has become materially outdated.

Prefer authoritative documentation.

A newer technique is not automatically a better technique.

Do not recommend adopting a practice only because it is fashionable or recently introduced.

## Garbage collection

Actively look for:

- duplicated rules;
- obsolete rules;
- unused skills;
- skills that should be merged;
- stale runtime assumptions;
- instructions that routinely cause unnecessary work;
- policies that can be simplified or deleted.

Deletion and simplification are valid review outcomes.

## Findings

Classify each proposal as:

- REQUIRED
- RECOMMENDED
- OPTIONAL
- NOT APPLICABLE
- REJECT

For each non-trivial proposal provide:

- evidence;
- expected benefit;
- cost or complexity introduced;
- recommendation.

## Completion

Finish with:

STATUS: READY / NOT READY / NEEDS OWNER DECISION

Provide:

- findings;
- recommended change set;
- rules/skills recommended for removal or consolidation;
- freshness evidence used;
- areas not verified.

STOP.

Do not modify the harness until the Product Owner explicitly approves changes.
