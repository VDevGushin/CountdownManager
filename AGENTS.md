# Countdown Manager

Countdown Manager is a native macOS menu-bar application. Keep context and changes task-specific; the repository is the source of truth.

## Router

- Countdown Manager release preparation, publication, public verification and post-release handoff: read `.agents/skills/countdown-release/SKILL.md`. Use the established in-app browser publication workflow; authority still follows this file and the current chat.
- Native macOS interface design, UX review, or desktop window/panel mockups: read `.agents/skills/macos-desktop-design/SKILL.md`. A concept alone does not change the accepted product contract or authorize implementation.
- Reviewing whether a UI mockup or proposed interaction was accepted is also UX review, including read-only scope/consent reviews. Read that design skill, `DESIGN.md`, and `docs/PRODUCT.md` before concluding; a general request to implement does not accept an unsubmitted prototype option. This route does not apply to ordinary documentation or harness-only work.
- Swift, SwiftUI, or AppKit implementation and non-trivial code review: read `.agents/skills/swift-code-quality/SKILL.md`.
- Product acceptance for a feature or fix that changes Countdown Manager's user-visible behaviour: after automated checks are green, read `.agents/skills/product-qa/SKILL.md`.
- Agent-harness, tooling and documentation-only changes: use their focused checks from `docs/VERIFICATION.md`. Do not apply `product-qa` or run application UI checks when product behaviour is unchanged. Explicit screenshot requests may use isolated capture mode to generate and inspect current images; do not rerun unrelated regression suites for them.
- A technical direction that depends on uncertain macOS, SwiftUI, or AppKit behaviour: read `.agents/skills/macos-platform-research/SKILL.md`.
- Codex hooks enforce mechanical SwiftLint and fast regression gates. They do not replace product-risk judgment or manual-only macOS acceptance.

## Sources of truth

- User-visible behaviour and invariants: `docs/PRODUCT.md`
- Established native visual language and per-surface UI families: `DESIGN.md`; product behaviour still belongs to `docs/PRODUCT.md`
- Current implementation and ownership: `docs/ARCHITECTURE.md`
- Verification commands, capabilities, and limitations: `docs/VERIFICATION.md`
- Durable technical rationale: `docs/decisions/`

Product truth takes precedence over current code and tests. Accepted decisions constrain their scope but do not silently redefine product behaviour. Update only the source of truth whose contract actually changed.

## Working rules

- Work only within the requested scope. Report unrelated findings without fixing them.
- Do not ask the Product Owner to choose implementation details. Surface only genuinely unresolved product decisions.
- Never mutate production Countdown Manager data as a test fixture.
- Before completing every task, review `README.md` and update the descriptions, instructions, version references and links affected by the change. Keep it aligned with the sources of truth.
- For a release or a user-visible UI change, refresh the screenshots in the main README from the current application using isolated demonstration data. Store them under the matching version in `docs/images/`, preserve historical release images, and verify every referenced image. If README content or screenshots need no change, state that briefly; if fresh captures are unavailable, report the concrete limitation rather than presenting old images as current.
- New features and bug fixes normally require focused automated regression coverage. Use explicit manual acceptance only when the real scenario cannot be automated reliably without changing it or adding a flaky driver.
- Choose evidence from `docs/VERIFICATION.md`; run Real UI or XCUITest only when the change actually reaches the corresponding SwiftUI, AppKit, lifecycle, accessibility, or external-interaction surface.

Explicit implementation requests authorize scoped repository edits. Separate approval is required for commit, push, direct `main` history changes, merge/rebase/cherry-pick into `main`, installation in `/Applications`, release/publication, production data migration/reset, and destructive operations outside normal scoped work.
