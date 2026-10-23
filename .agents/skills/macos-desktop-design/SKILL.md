---
name: macos-desktop-design
description: Design and review native macOS desktop interfaces, window and menu-bar workflows, keyboard interaction, and desktop mockups in Countdown Manager. Use for native UI/UX decisions; leave Swift implementation to swift-code-quality and unrelated websites or mobile interfaces to their own design workflows.
---

# macOS Desktop Design

Design desktop interfaces around the user's task, macOS interaction conventions, and the existing product identity. A larger window needs a useful composition, not just an enlarged panel.

## Establish the scope

Read the relevant parts of `docs/PRODUCT.md`, `DESIGN.md`, and the affected implementation or current captures. For lifecycle changes, also read the applicable decision in `docs/decisions/` and `docs/ARCHITECTURE.md`. Product contracts and current native implementation resolve stale illustrative design guidance.

Distinguish an idea, an interactive mockup, and a requested native implementation. A mockup does not authorize implementation or change accepted product behaviour. Report a conflict with the accepted contract as a proposal; do not silently turn it into a new requirement.

Infer routine design choices from the task and established interface. Ask only about unresolved product choices that would materially change the result. Do not make the owner choose framework APIs, pixel values, or a design workflow.

## Give each surface a job

Choose a window, temporary panel, inspector, or settings surface according to the work it supports. Preserve existing roles unless the requested change calls for a new one.

For a proposed desktop window alongside a menu-bar panel, establish:

- what the panel makes quick and what the window makes easier;
- how the user opens, closes, and returns to each surface;
- which data and actions are shared, and which browsing or selection state belongs to each surface;
- where an unsaved editor lives and what happens if another surface edits or deletes that event;
- the meaning of close, hide, Save, Cancel, and Quit;
- expected launch, Dock, application-switching, and Space behaviour where relevant.

Reuse one product and its data owners. Separate views do not imply separate applications, duplicated timers, new accounts, or a synchronization service. Surface genuine conflicts between simultaneous edits instead of promising that sharing a data file solves them.

Do not add an archive, recurrence, reminders, categories, or calendar-replacement behaviour merely to fill a larger window. These are separate product decisions.

## Compose for desktop work

Use the existing palette, calendar leaves, typography, semantic colors, and component roles. Carry identity into the new composition without copying every compact-panel dimension into a large window.

Choose a list, split view, detail area, or inspector when it serves actual content. Keep selection, the current task, and primary actions visible. Avoid navigation sections with no real destinations and decorative dashboard metrics.

Design resizing from content: identify a useful minimum window size, flexible columns, text wrapping, scrolling ownership, and long-content behaviour. Check the actual review viewport as well as the proposed desktop size. A narrow browser preview is not evidence that the macOS app needs a mobile interface.

Prefer native window chrome, toolbar actions, menus, text fields, checkboxes, date controls, selection, and focus behaviour when they fit. Preserve platform editing and keyboard conventions. Avoid duplicate field borders and simulated native controls in production code.

Keep the ordinary and failure states useful: no events, no selection, search without results, long titles and notes, an unavailable selected event, a pending or failed save, and incomplete preparation. Select only states relevant to the change.

## Keyboard, accessibility, and appearance

Account for logical keyboard focus, visible focus indication, selection versus activation, labelled icon actions, and the existing save/cancel/close commands. Do not assign competing shortcuts or steal text-editing commands to drive navigation.

Use native text roles and legible content hierarchy rather than importing web pixel floors into macOS points. Check truncation, control labels, contrast, Light/Dark appearance, Increase Contrast, and Reduce Motion where the changed surface depends on them. Do not claim accessibility from visual appearance alone.

## Use design tools at their actual scope

Impeccable may help composition and visual critique when available. Lavish may provide a reviewable HTML mockup when requested or useful. Neither is a required dependency for native design work.

Label HTML mockups and synthetic data clearly. Demonstrate important interactions when that helps assess the design. Keep proposal notes outside the product's everyday interface, and describe controls that are illustrative rather than functional.

HTML/CSS detectors evaluate the mockup, not SwiftUI or AppKit. Inspect the rendered result before changing native-inspired chrome to satisfy a web heuristic. Fix real defects; scope any justified detector exception to the specific artifact and disclose it. Do not disable a rule globally or treat a web report as native acceptance evidence.

## Hand off and verify

For a concept, deliver the visual artifact, the important interaction choices, and any unresolved product decision. Do not run application regression suites for a mockup-only change.

For implementation, use `.agents/skills/swift-code-quality/SKILL.md`. Investigate uncertain platform mechanics with `.agents/skills/macos-platform-research/SKILL.md` before depending on them. After the applicable automated checks pass, use `.agents/skills/product-qa/SKILL.md` and the evidence map in `docs/VERIFICATION.md`.

Inspect captures at their real scale and record whether they show HTML, a native test fixture, or the actual isolated app build. Window activation, close/reopen, real status-item interaction, focus, and Space behaviour need evidence capable of exercising those interactions; screenshots alone cannot establish them.

Update product or design sources only for accepted changes in their scope. Follow `AGENTS.md` for README and current native screenshot requirements; an unimplemented concept does not become a shipped feature in those documents.

## Platform references

Consult the relevant current first-party guidance when the decision needs it, rather than loading a whole manual for every task:

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

If documentation is unavailable, state the unresolved limitation rather than inventing an Apple recommendation.
