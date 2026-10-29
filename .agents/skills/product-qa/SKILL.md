---
name: product-qa
description: Validate Countdown Manager product changes after automated checks pass and review whether affected regression tests protect the current contract, selecting useful evidence without redundant runs.
---

# Product QA

Use this skill for product acceptance after the relevant automated checks are green, or for an explicitly requested review of regression-test relevance.

Documentation-only and harness-only changes do not need product acceptance or application UI checks. A test-relevance review uses the guidance below and the focused tooling checks from VERIFICATION; it does not require launching the app merely to review tests.

## Start from the project map

Read `docs/VERIFICATION.md` before choosing evidence. It defines the commands, capabilities, limitations, isolation requirements, and manual-only macOS scenarios available in this repository.

Identify the changed product contract and its credible failure modes. Then choose only the verification surfaces that can exercise those risks. Real UI verification is warranted only when the change actually affects SwiftUI, AppKit, application lifecycle, event routing, focus, accessibility, animation, or other runtime behaviour.

Do not treat a configured property, code path, screenshot, or internal test action as proof of an external macOS interaction that the selected driver cannot faithfully deliver.

## Check that the tests still protect the current contract

Before selecting additional checks or accepting existing passes, inspect the affected test bodies,
fixtures, assertions and driver limitations. A test name, historical PASS or a large suite count
is not evidence that the changed behaviour is covered.

For each important changed risk, connect the current PRODUCT/DESIGN contract or technical invariant
to the test's trigger and observable failure. Keep this mapping briefly in work notes; do not create
a separate permanent registry for every task. Identify which realistic defect would make the test
fail. For example, a countdown-value assertion cannot establish that its emoji is not clipped.

- Keep regressions for old bugs while their invariant still applies. Tests preventing removed UI
  from returning can remain valid; an old version/date in a fixture alone does not make it obsolete.
- When accepted behaviour changes, update the affected expectations, fixtures and meaningful
  negative/boundary cases together. Verify the new expectation against the contract, not merely
  the implementation's current output. Never weaken an assertion or change product behaviour
  solely to obtain green results.
- If no selected check can detect the changed failure mode, add focused coverage at the right
  boundary or identify the concrete automation limitation and manual acceptance. For a new or
  materially changed regression, demonstrate rejection of the reported defect when practical
  through its pre-fix reproduction or a focused mutation; do not require broad mutation runs.
- Replace or remove a test only after establishing that its protected requirement was retired,
  or another retained test exercises the same failure with no lost boundary/platform coverage.
  Distinguish a redundant test from a valid test that is simply unrelated to this task.

Use the smallest sufficient combination of checks and reuse valid evidence. Required hook/static/
fast gates still apply; relevance review is not permission to bypass them. Read verify.sh when
combining commands: overlapping wrappers are not additional independent coverage. Do not call
unchanged tests current merely because they passed; report the actual scope inspected.

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

## Compare the new UI with its existing sibling

For an added or changed UI family, name the existing control/section used as the reference and
compare it on each affected surface. Check symbols and native treatment, header/count alignment,
disclosure/default state, full click area and empty/one/limit content. A visible list screenshot
does not prove collapse or hidden-row accessibility. Exercise the applicable interactions; verify
that disclosure changes no event bytes and that hiding/reopening follows the established contract.
Do not import desktop presentation into the mini-panel or a mini disclosure into desktop details
without a product reason. Confirm the reviewed build's SDK/style matches the ordinary build path.
When delivering a tester app, verify its actual launcher and packaged native bundle, not only the
underlying build. Preserve LaunchServices registration and the isolated home; a shell wrapper
executing a raw Cocoa executable is not equivalent evidence for status-item/panel anchoring.


## Observe transitions, not just settled states

When a changed flow includes asynchronous saves, pending controls, or redraws, observe representative actions during the transition as well as after completion. Include rapid repeated input when relevant. Look for brief flashes, unrelated controls dimming or disabling together, blank frames, layout jumps, and lost focus. A passing end-state assertion or settled screenshot cannot establish that a transition is visually stable.

For a reported visual transient, inspect the supplied recording around the action frame by frame when available. Identify the affected region and timestamps, and distinguish unintended flashes from expected press feedback or modal dimming. Reproduce with isolated data; do not mutate the user's production data to investigate.

Add focused regression coverage for the actual intermediate failure state. Prefer controlled asynchronous boundaries over timing-dependent sleeps. Pair state assertions with bounded render observation or a specific manual transition check when the driver cannot faithfully capture the effect; internal flags alone do not prove the absence of flicker. Preserve persistence, editor ownership, and rapid-input semantics rather than masking the symptom by removing safety guards or silently dropping input.

Apply this proportionately to the affected interaction, not as a requirement to record every task. State which transitions were actually observed and which remain unverified; do not report “no flicker” based only on final-state captures.

## Separate agreement, implementation and appearance

Validate the user's accepted scope separately from implementation behavior. A prototype's default
selection and passing tests written for an agent's own addition are not acceptance evidence.
Check that unrequested mutation/undo/status mechanics have not appeared in the new flow.
For native style acceptance, compare the actual build's recorded compiler SDK, linked compatibility
and shared component family with the accepted reference. A version change alone does not authorize
a new visual identity. Run the design-system/contract gates from docs/VERIFICATION.md; do not infer
runtime appearance from shared source code or SDK metadata alone. Review native captures in the
required themes and contrast states before reporting visual parity.

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
