---
name: product-qa
description: Validate Countdown Manager product changes after automated checks pass, selecting project-specific test and manual surfaces without repeating valid evidence.
---

# Product QA

Use this skill for product acceptance of a feature, bug fix, or user-visible behaviour change. It acts as a focused human QA pass after the relevant automated regression checks are green.

Do not use it for documentation-only, harness-only, or other changes with no product behaviour to accept.

## Start from the project map

Read `docs/VERIFICATION.md` before choosing evidence. It defines the commands, capabilities, limitations, isolation requirements, and manual-only macOS scenarios available in this repository.

Identify the changed product contract and its credible failure modes. Then choose only the verification surfaces that can exercise those risks. Real UI verification is warranted only when the change actually affects SwiftUI, AppKit, application lifecycle, event routing, focus, accessibility, animation, or other runtime behaviour.

Do not treat a configured property, code path, screenshot, or internal test action as proof of an external macOS interaction that the selected driver cannot faithfully deliver.

## Regression coverage is the default

A new feature should add or update automated coverage for its important observable behaviour. A bug fix should include a regression test that fails for the reported defect and passes with the fix.

The exception is a scenario that cannot be automated reliably without changing the contract under test or introducing a flaky driver. State that limitation explicitly and define a short manual acceptance check tied to the changed behaviour. Do not distort production code to make an unreliable automation path possible.

## Explore like a user

After automated checks pass, exercise the relevant combinations from these lenses:

- happy path;
- invalid or negative input;
- reverse or undo direction;
- meaningful boundaries and limits;
- launch, hide/show, reopen, focus, and other relevant lifecycle transitions;
- accessibility semantics and keyboard operation;
- Reduce Motion when animation or motion communicates state;
- rapid repeated actions and duplicate delivery;
- sibling features and unexpected action ordering near the changed flow.

This is a risk lens, not a mandatory checklist. Skip dimensions that cannot affect the change and explain only material omissions.

Prefer observable outcomes over implementation details. Watch for stale state, duplicated effects, lost drafts, incorrect focus, inaccessible controls, animation that ignores Reduce Motion, and regressions in adjacent flows sharing the same state or component.

## Preserve valid evidence

Do not rerun evidence that is still valid merely to make the report look complete. Reuse it when the relevant code, configuration, build provenance, environment, and failure mode have not changed.

Rerun a check when its subject changed, its previous run failed or was interrupted, the exercised bundle is stale or unknown, the environment materially changed, or a new risk appears.

Never use production Countdown Manager data as a mutable test fixture. Follow the isolation requirements in `docs/VERIFICATION.md`.

## Report

Report only:

- the behaviour accepted;
- automated and manual evidence used, including any intentionally reused evidence;
- failures or material sibling regressions;
- behaviour that remains manual or unverified, with the concrete limitation.
