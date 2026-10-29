# Release workflow validation — 2026-10-30

The owner requested a reusable project release skill after the timer glyph escape and outdated
GitHub homepage. They explicitly retained in-app-browser publication and requested cleanup plus
the previous installed release for their personal update after successful publication.

Created `.agents/skills/countdown-release/` and routed release tasks from AGENTS. Detailed
channel/signing mechanics remain in UPDATES; product/design/QA contracts are not duplicated.
The skill keeps authorization in AGENTS and current chat, and treats the owner's handoff as a
default they can override. It does not grant publication or data-migration permissions.

Validation:

- Official skill-creator structural validator: valid.
- Five isolated helper regression fixtures passed: current references, obsolete existing homepage
  image, native help-ID mismatch, broken local link and a stale actual default-branch README.
- Final repository local check: 113 Markdown files, 434 local references, four current-version
  homepage images; zero errors.
- Independent read-only forward-test covered a release branch ahead of main with pre-signing
  screenshots, and Published-click plus a correct previous installation and mixed cleanup paths.
  No blocking workflow defect found. It correctly required missing evidence, preserved current
  chat authority, retained the already correct previous installation and excluded unrelated
  temporary data/receipts. No production operation was executed by the evaluator.

This validates structure, deterministic checks and the two dry-run decisions. It is not a claim
that every future release or macOS environment is automatically certified. The actual 1.20.3
publication has its own public-byte receipt; subsequent uses must read current state again.
