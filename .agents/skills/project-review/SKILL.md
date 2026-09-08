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

Finish with:

STATUS: READY / NOT READY / NEEDS OWNER DECISION

Then provide:

- findings;
- recommended change set;
- what was inspected;
- what was not verified.

STOP.

Do not implement findings until the Product Owner explicitly approves a change set.
