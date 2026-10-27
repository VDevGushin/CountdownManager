# Native style harness audit — 2026-10-27

Scope: the links feature exposed two review failures: the HTML trash icon differed from the
existing native symbol, and the mini-panel links section initially lacked the established
disclosure behavior. This audit accompanies the corrections; it is not a release certification.

## Findings

1. Existing design guidance already required reading the current native implementation and using
   established controls. It was not applied consistently. Generic palette/type guidance did not
   force a concrete sibling comparison for a new block on each surface.
2. The initial link acceptance exercised rendering and editor persistence, but did not encode
   collapsed/default/hidden-row behavior or the 10-link mini-panel density boundary. Lint and
   pure state checks could not detect this interaction mismatch.
3. The new HTML concept used a hand-drawn trash despite the app already using SF Symbol `trash`.
   The HTML was corrected to the exported native symbol during review; production uses `trash`.
4. A new-SDK Xcode Debug preview adopted different system control styling. Product screenshots
   must come from the ordinary build path with recorded SDK/executable provenance; a successful
   Debug behavioral test is not visual authority for the shipped product.

## Changes to the harness

- `AGENTS.md` now names `DESIGN.md` as the visual and per-surface UI-family source; PRODUCT remains
  authoritative for behavior.
- The macOS design skill requires a named existing sibling on every affected surface, including
  state/default/count/click-area/hidden-content comparison, existing icon resources and build style.
- The Swift skill requires this comparison before UI coding. It does not force desktop and panel
  to have identical interactions or require a speculative shared abstraction.
- Product QA now checks the implemented sibling relationship, symbols, zero/one/limit cases,
  interaction reversals, hidden rows and unchanged bytes. A screenshot alone is insufficient.
- Eval suite version 5 adds `mini-desktop-style-boundary`: a read-only review of an intentionally
  inappropriate universal layout and replacement icons. Its rubric checks concrete source use,
  surface boundaries, icon authority and evidence limits. No live model run has been performed;
  passing schema/infrastructure tests does not establish future agent behavior.

## Product regression coverage

The mini-panel now uses the existing attachments family: fixed chevron, 12-point semibold heading,
trailing neutral count and a full-width disclosure button. It starts collapsed; hide/show retains
mounted state and collapsed rows leave interaction/accessibility. Desktop details remain expanded.
Desktop grid/feed/favorite also use the existing neutral material-summary family for link counts:
system `link`, 11-point medium count, no zero placeholder, no separate action.

The native link sequence checks repeated disclosure, hidden-row removal, heading/count horizontal
alignment, ordinary hide/show retention and unchanged event JSON. It additionally checks positive
and absent desktop link summaries, coexistence with checklist/files, and containment in the
existing summary host in collection/feed. Current captures cover Light/Dark and both mini states.

`testMiniLinksDisclosureAtZeroOneAndTenPreservesData` passed in an external run: ordinary header
and trailing-count clicks at 0/1/10 links, reverse direction, hidden rows and unchanged JSON.
Its first run completed its body but failed when teardown requested a screenshot after the test
had already terminated the app. The test now leaves the final app lifetime to normal teardown;
the corrected run passed 1/1 in 24.596 seconds. Neither failure nor success is a combined suite.

## Harness validation and remaining limits

- Eval infrastructure: 33 deterministic checks passed.
- Swift hook regressions: 12 checks passed. Hook registration/configuration was not changed.
- Three edited skill entrypoints passed `skill-creator/scripts/quick_validate.py`. PyYAML was
  installed only in a temporary validation environment after the system Python lacked it.
- No test merely asserts that the new instructions contain particular wording. The product
  regression checks assert actual rendered/native states and unchanged persistence bytes.
- No live agent eval or native hook-delivery campaign was run. This closes a concrete coverage
  gap, not a guarantee that every future design decision is correct.
- The earlier desktop failure is now resolved in a separate full **28/28** run. Dynamic desktop
  event controls use native registration updates rather than stale appearance/change callbacks.
  The earlier failing results are preserved; they were not relabeled as successful. A final
  external links campaign also passed **3/3** after the value-before-symbol styling change.

See [current native evidence](../images/v1.18.1/event-links-unreleased/completion/PROVENANCE.md).

## Delivered tester parity correction

A later user check exposed a delivery-only mismatch: the wrapper executed a raw Cocoa executable,
so the tester's status item/panel anchor was not equivalent to a LaunchServices-launched native
bundle. The repaired launcher opens its nested native app through LaunchServices with the same
isolated home. The user confirmed the icon/anchor returned. Product QA now explicitly requires
verification of the delivered launcher. This did not require changing panel positioning code.

Further accepted detail-header refinement uses a single `SavedMaterialHeading` for files/links
with required count and symbol, sharing metadata ordering with checklist progress. Both card
summaries and detail headers are checked by actual native frame assertions. The mini-panel
retains its disclosure family. These are behavioral/rendered checks, not assertions of prose.
