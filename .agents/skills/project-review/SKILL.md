---
name: project-review
description: Read-only engineering review of Countdown Manager architecture, code, tests, lifecycle, persistence and maintainability.
---

# Project Review

## Purpose

Evaluate the current engineering health of Countdown Manager without changing the project.

This skill is READ-ONLY by default.

## Inputs

Required:

- current repository state;
- `COUNTDOWN_MANAGER.md`.

Load additional code, tests, documentation and diagnostics only as needed.

Do not read the entire repository mechanically before forming review questions.

## Review

Inspect proportionately:

1. correctness and product invariants;
2. persistence and user-data safety;
3. architecture and unnecessary complexity;
4. SwiftUI/AppKit lifecycle;
5. concurrency and ordering;
6. error handling and diagnostics;
7. accessibility where relevant;
8. test strategy and test cost;
9. stale workarounds and technical debt;
10. documentation consistency.

Do not treat code volume, abstraction count, test count or coverage percentage as quality metrics.

## Test review

Classify relevant existing tests as:

- KEEP
- MERGE
- SIMPLIFY
- MOVE DOWN
- REMOVE
- MISSING

Prefer the cheapest reliable layer that protects the intended contract.

Do not recommend duplicate coverage unless different layers protect against materially different failure modes.

Do not run expensive UI or XCUITest suites merely because they exist. Run checks only when they provide evidence needed by the review.

## Independent completion review

When acting as the independent reviewer for completed implementation changes, review two distinct aspects:

1. architecture and code correctness;
2. adequacy of verification evidence against the actual user contract, using the ladder, trigger and bundle-provenance rules in `VERIFICATION.md`.

Reject `READY` when a test substitutes an implementation hook for the user action under test, exercises a stale or different bundle, verifies a lifecycle defect only with internal smoke, omits required installed black-box evidence, or omits separately required platform integration evidence. The implementer's own internal test cannot by itself conclusively establish user-visible lifecycle behaviour.

Report the independent-review result using the applicable READY contract in `VERIFICATION.md`; do not transfer a missing gate to Product Owner manual testing.

## Findings

Classify findings as:

- BLOCKER
- IMPORTANT
- CLEANUP
- OPTIONAL

For each actionable finding provide:

- evidence;
- impact;
- recommended action;
- relevant trade-offs.

Distinguish FACT, HYPOTHESIS and VERIFIED according to `COUNTDOWN_MANAGER.md`.

## Completion

Finish a standalone project review with:

STATUS: READY / NOT READY / NEEDS OWNER DECISION

Then provide:

- findings;
- recommended change set;
- what was inspected;
- what was not verified.

STOP.

For an independent completion review, instead finish with the applicable independent-review and READY fields required by `VERIFICATION.md`, then stop.

Do not implement findings until the Product Owner explicitly approves a change set.
