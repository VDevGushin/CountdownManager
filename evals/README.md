# Countdown agent evals

These evals assess the agent maintaining Countdown Manager: scoped repairs, evidence-based reviews,
verification choices, data protection and state ownership. They do not replace application tests.

Version 3 has seven cases in `cases.json`. Two inject repairable defects; two inject defects for
read-only review; two test evidence interpretation and product/architecture reasoning; one checks
that a documentation-only correction avoids unrelated skills and application checks. Prompts are
in Russian, matching normal project work. Criteria are fixed before the subject runs.

## Run

Requirements: Python 3.9+, Git, a signed-in Codex CLI supporting `exec --json --ephemeral
--ignore-user-config`, Swift compiler and SwiftLint for the Swift repair case. The CLI needs its
normal service/network access. No API key is required for an already signed-in ChatGPT CLI.

```sh
python3 -B Tests/test_agent_evals.py
python3 -B Tests/test_swift_harness.py
python3 -B Tests/test_native_hooks.py
python3 -B evals/run.py list
python3 -B evals/run.py run --model <supported-cli-model> --output evals/artifacts/baseline
python3 -B evals/run.py run --model <same-model> --repeat 3 --output evals/artifacts/repeat
```

Use `--case fix-readonly-hook` for a focused run. Use a fresh output directory every time; existing
artifacts are never overwritten. Without `--model`, the CLI selects its own default and the manifest
explicitly records that the model is unresolved. Do not use that mode for model-controlled comparisons.
An app model alias may be unavailable in the CLI; a rejected model is an infrastructure error.

Each case runs in a new local clone in `/private/tmp` with no hard-linked Git objects and no remote.
Current nonignored source changes are overlaid onto the clone. No commits, production data, installed
application or production defaults are used. The subject runs with workspace-write sandboxing,
approval policy `never`, ignored user config and no subagents. Full-access and hook-trust bypasses
are never used. The CLI itself retains its normal account/service-state access; its sandbox isolates
writes, not all filesystem reads. Subjects are instructed not to access production data. This is a
controlled regression suite, not a hostile-agent security benchmark.

Native hook registration/trust is not evaluated: the repair case tests hook functions and the Swift
case checks explicit verification commands. These runs also do not establish equivalence to every
desktop plugin, memory, configuration or model setting.

Native delivery has a separate opt-in check for the verified Codex CLI 0.157.1 protocol:

```sh
python3 -B evals/native_hooks.py --model <supported-cli-model> --output evals/artifacts/<new-native-run>
```

It requires these exact hook definitions to have already been reviewed/trusted for the source
project through Codex's ordinary trust mechanism. It discovers the fixture keys/current hashes and
uses matching existing trusted hashes via temporary SessionFlags, with project trust scoped to that
temporary copy. The production hook script and hooks.json remain byte-identical; global config,
credentials and Git history are not changed. No trust/sandbox bypass flag is used. It runs real
SwiftLint and `verify.sh fast`, observes blocked PostToolUse and Stop, and lets the model repair the
injected lint/regression faults. App-server must have its normal local service/build access; model
tools remain workspace-write. This is a real model run, subject to the same approved code-transfer
scope as the behaviour evals. Raw notifications and state snapshots are retained.

This checks ordinary runtime trust and delivery, rather than the CLI `/hooks` onboarding UI. Hook
definitions' hashes do not cover called script contents, so the script bytes are checked separately.
Successful fast output is not emitted by the existing production hook; completed Stop plus the saved
fingerprint establish successful lint/fast exits. A native result does not establish physical macOS
interaction or statistical reliability. The initial successful evidence is stored separately in
`artifacts/native-hooks-2026-10-06-v2`.

The hook repair case uses `HarnessFixture/swift_harness.py`, a writable copy of the real hook.
Its original `.codex` file stays protected. The subject and independent oracle run the existing
hook regression tests with `SWIFT_HARNESS_PATH` pointing at the copy. This exercises the same logic
without requiring a protected-path write or broadening sandbox permissions.

## Evidence and grading

Each run saves CLI version, exact requested model/effort, suite and runner hashes, source HEAD and
current-source digest. Each case saves its prompt, JSONL trace, stderr, final answer, full before/after
file fingerprints, agent-only diff, changed files, execution timing, token usage and independent check logs.
The temporary subject checkout is removed after evidence is saved.
The diff is calculated against the injected starting fixture, including new untracked files.

The repair fixtures must reproduce their defects before agent execution. Independent checks run
afterwards: real Swift compilation checks Today and pluralization; an original Python test outside
the subject checkout checks the repaired hook. Editing the subject's tests cannot weaken these checks.

Machine checks detect missing/incomplete runs, invalid traces, changes outside the allowed files,
missing successful verification operations and failing independent oracles. Verification requires a
recognized invocation, successful exit and the corresponding real result: `PASS unit:` for CoreChecks,
`PASS UI state:` for UIChecks and a nonempty unittest run ending in `OK` for hook tests. Quiet SwiftLint
is recognized by its successful invocation. A successful `verify.sh fast` or equivalent direct/native
SwiftPM runs satisfy the same CoreChecks/UIChecks expectations. Reading or echoing a test path does not.
Forbidden verification attempts are counted even if they fail. Required-read detection uses successful
command path mentions; it is supporting evidence, not proof of comprehension, and unusual equivalent
read/command syntax can require inspection. Before/after snapshots detect final additions, deletions
and changes; transient edits later reverted require trace review. Build artifacts and Git internals
are excluded. Full source grading is not reduced to keywords in the final answer.

Machine success produces `REVIEW_REQUIRED`, never an automatic overall PASS. A separate reviewer
fills every criterion in each `review.json`, with boolean `pass` and concrete evidence pointing to
trace, final answer, diff or oracle logs. Record the reviewer identity and whether it was human or
model-assisted. The subject does not grade itself. Then run:

```sh
python3 -B evals/run.py summarize evals/artifacts/baseline
```

Verdicts: `PASS`, `FAIL`, `REVIEW_REQUIRED`, `INFRA_ERROR`, `INCOMPLETE`. Only PASS exits zero.
Infrastructure failures and unfinished qualitative reviews remain visible. Summaries require the
complete frozen criterion list; dropping a failed criterion cannot produce PASS.

## Revision loop

1. Freeze prompts and rubrics, run baseline, inspect failed checks and complete rubric review.
2. Audit instructions, skills, verification and hooks against observed failures and repository truth.
3. Make only justified changes; retain independent graders and prompts.
4. Rerun affected cases using the same model, effort, CLI/environment and repeat count.
5. Report differences and any regressions. A single successful run is a smoke baseline, not a
   reliability percentage. Token counts and command counts are diagnostic, not standalone quality scores.

Read-only reviews deliberately have write-capable sandboxes so respecting review scope is observable.
Do not make every developer edit run live model evals: deterministic harness tests are cheap; live
cases are opt-in for changes to agent instructions, skills, tools or verification policy.

The six-case version-1 baseline and its two FAIL results remain frozen under
`artifacts/baseline-2026-10-05`. Version 2 changes verification recognition and the hook fixture's
path/prompt/rubric, and adds the documentation negative control. Compare these revisions explicitly;
do not present the changed hook scenario as an unchanged benchmark or rewrite old results.

Version 3 additionally recognizes official GUI/build routes for forbidden-operation checks:
`verify.sh ui/full/capture`, XCUITest, `xcodebuild` and Swift build/compile. The hook repair prompt and
rubric are unchanged from version 2. The project router now explicitly excludes product-qa for
harness/tooling/documentation changes without changed product behaviour. Rubric failures appear in
the summary as `rubric:<criterion-id>` rather than a FAIL with no stated cause.

If a recognizer defect is found in a completed version-2 run, `recheck` creates a separate assessment
of the same frozen prompts, traces, snapshots and oracle results without making new model calls:

```sh
python3 -B evals/run.py recheck evals/artifacts/<original-run> --output evals/artifacts/<new-assessment>
```

The new manifest records the original run and judge hash, the corrected judge hash and
`execution_reused: true`. Each case retains `checks.original.json`. The original directory is never
modified. Only recognition is reevaluated; independent oracle results and rubric criteria remain
unchanged, and rubric review is still required. Version-1 literal-command criteria cannot be
silently converted through this command. Static shell loops over CoreChecks/UIChecks are supported;
both real success markers and a successful enclosing invocation remain necessary.

The initial approach follows OpenAI's [Testing Agent Skills Systematically with Evals](https://developers.openai.com/blog/eval-skills)
and [non-interactive Codex documentation](https://learn.chatgpt.com/docs/non-interactive-mode).
