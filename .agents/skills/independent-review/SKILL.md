---
name: independent-review
description: Run an independent, read-only acceptance review of a scoped Countdown Manager task with a fresh reviewer. Use when the user asks for independent review, including «нужно независимое ревью», or invokes this skill by name.
---

# Independent review

The reviewer makes a separate acceptance decision and returns evidence to the orchestrator. The orchestrator owns any follow-up fixes.

## Orchestrate the review

1. Identify the task under review from the user's command or the active task. Collect the original request, accepted clarifications, the workspace or artifact paths, and the candidate's base and changed files. Include staged, unstaged and relevant untracked files when the task is in the working tree. Leave parallel work outside the review scope. Give the reviewer a stable candidate or record what changed during its review.
2. Launch a new reviewer with an empty conversation context. Use a new subagent with `fork_turns: "none"`. If the user explicitly requested a separate Codex chat, create a new local chat and collect its result there. Give the reviewer only the candidate, the user-approved scope, the relevant raw evidence and execution constraints. Exclude prior verdicts, suggested findings and implementation history. Point it to this skill's **Reviewer** section. Assign read-only access to the candidate and allow temporary isolated verification within the task scope.
3. Collect the review before making the acceptance decision. Assess each finding against its evidence, reproduce consequential failures when feasible and resolve disagreements with a targeted check. If the active task authorizes fixes, fix confirmed in-scope defects, verify the corrected and neighboring cases, and send material changes for a fresh follow-up review. If the user requested review alone, deliver the findings. State the specific limitation whenever independence or required verification is unavailable.

## Reviewer

You are the independent reviewer. Review the supplied candidate and return an acceptance decision to the orchestrator.

- Read the user-approved scope, the candidate's `AGENTS.md` and the affected contracts first. Inspect the actual change and its normal entry points. Select the relevant guidance for Swift, native interface design, verification and harness-only work through the repository router.
- Try to disprove readiness. Follow the paths most likely to lose data, accept an unauthorized scope change, act on the wrong target, drop input or mislead the user. Probe applicable boundaries, stale state, concurrent actions, error and retry, Cancel, cleanup, older data and adjacent workflows. For features with two surfaces, check each affected surface and their shared ownership. Test negative and reverse paths where they can expose a defect. Use isolated data and the smallest evidence surface capable of reproducing each issue. Coordinate interactive desktop runs with the orchestrator.
- Read the actual test assertions and fixtures. Establish whether they could catch the failure in question. Separate a reproduced defect from a definite code inference or an open verification gap. Check relevant new changes against the accepted product and design contracts.
- Preserve the candidate, installed application and production data. Write any probes or evidence in temporary isolated locations. If the candidate changes while you work, identify exactly what your conclusions cover.
- Return a verdict of **changes required**, **accepted within reviewed scope**, or **inconclusive**. Order actionable findings by severity. For each, give the source or artifact location, minimal reproduction or triggering conditions, expected and observed result, user impact, and the criterion for closing it. List verification limits separately. A clean review can report no actionable findings.

Independent review is user-triggered. Select existing checks through `docs/VERIFICATION.md` and respect the repository's approval boundaries. Routine product QA, broad monkey QA and the mechanical completion checks retain their own routes.
