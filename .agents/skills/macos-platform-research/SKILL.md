---
name: macos-platform-research
description: Research uncertain macOS, SwiftUI, or AppKit behaviour when that uncertainty materially affects a technical decision in Countdown Manager.
---

# macOS Platform Research

## Purpose

Use this skill when a technical decision materially depends on behaviour of macOS, AppKit, SwiftUI, or their interaction and that behaviour is not already established with sufficient confidence.

The goal is to answer the smallest platform question needed to make the engineering decision.

This skill is not a general research phase for every macOS change.

## Use this skill when

Typical triggers include uncertainty about:

- `NSPopover`;
- `NSWindow`;
- sheets or modal presentation;
- focus and first responder;
- application activation;
- status-item interaction;
- mouse or keyboard routing;
- SwiftUI/AppKit interoperability;
- accessibility behaviour;
- drag and drop;
- system services;
- lifecycle during hide, reopen, wake, activation, or termination.

Use it only when the uncertainty can materially change architecture, implementation mechanism, correctness, user-visible behaviour, or required verification.

## Do not use this skill when

Do not invoke platform research for:

- pure domain logic;
- validation;
- JSON encoding or decoding;
- ordinary persistence logic;
- deterministic presentation transformations;
- code that already has a clear established platform contract;
- questions answerable directly from the existing repository implementation and accepted decisions.

Do not research macOS APIs merely because the application is a macOS application.

## Inputs

Start with the current task.

Load only the repository context needed to understand the platform question.

Relevant sources may include:

- `docs/PRODUCT.md`;
- `docs/ARCHITECTURE.md`;
- a directly relevant accepted decision;
- the affected implementation;
- relevant verification code.

Do not load unrelated application code or every historical decision.

## Step 1 — Define the platform question

State the uncertainty precisely.

Good:

> Does a transient `NSPopover` preserve its hosted SwiftUI hierarchy when it closes normally, or is our code explicitly replacing that hierarchy?

Good:

> Can the current XCUITest environment perform the outside interaction required to prove transient dismissal?

Bad:

> Research popovers.

Bad:

> Figure out how SwiftUI works.

The question should be narrow enough that answering it changes a concrete technical decision.

## Step 2 — Separate known facts from assumptions

Before external research, identify what is already known from the repository or direct observation.

Use simple categories when useful:

**Known**
- directly visible in current code;
- directly documented by an authoritative source;
- directly reproduced.

**Assumption**
- plausible but not yet established.

Do not create a large evidence taxonomy.

The important distinction is whether the technical decision currently rests on evidence or assumption.

## Step 3 — Gather authoritative evidence

Prefer evidence in this order:

1. current Apple documentation;
2. Apple Human Interface Guidelines where user interaction semantics are relevant;
3. Apple release notes or framework documentation;
4. direct observation on the supported macOS runtime;
5. existing Countdown Manager implementation, diagnostics, and accepted decisions;
6. official Swift documentation when relevant;
7. high-quality secondary sources only when primary evidence is insufficient.

Prefer current documentation when framework behaviour may have changed across macOS or SwiftUI releases.

A community workaround is not proof of platform behaviour.

## Step 4 — Check repository history only when it matters

Historical Countdown Manager evidence may be useful when:

- the same failure mode occurred before;
- an existing architectural restriction refers to a past platform issue;
- a current decision cannot be understood from its recorded rationale;
- regression history materially changes the risk of an implementation choice.

Do not reconstruct project history by default.

Git history is supporting evidence, not permanent architecture authority by itself.

## Step 5 — Use a minimal experiment when documentation is insufficient

If the material platform question remains unresolved, prefer a small experiment that isolates that question.

A good experiment:

- changes one relevant variable;
- exercises the actual platform mechanism;
- has an observable result;
- avoids building production architecture around the hypothesis.

Examples:

- minimal transient-popover lifecycle reproduction;
- responder-state inspection before and after sheet dismissal;
- focused XCUITest proving whether a specific external interaction is accessible;
- small SwiftUI/AppKit host reconstruction experiment.

Do not build a workaround and call it a spike.

The experiment should answer the question, not become the solution automatically.

## Read-only contexts

If this skill is being used during a task that is explicitly read-only:

- do not modify repository files;
- do not create an experimental implementation in the repository;
- describe the smallest experiment that would resolve the uncertainty;
- stop at the point where execution would require write authority.

External documentation research and safe read-only inspection remain allowed.

## Step 6 — Reach a technical conclusion

When sufficient evidence exists, state:

### Question

The exact platform question investigated.

### Evidence

Only the evidence that materially supports the conclusion.

### Conclusion

What the platform evidence supports.

### Engineering consequence

How that evidence affects the current technical decision.

### Remaining uncertainty

Anything still unknown that could materially alter the decision.

If no material uncertainty remains, say so.

## Step 7 — Identify verification implications

Use `docs/VERIFICATION.md` to identify the lowest verification surface that can actually exercise the changed failure mode.

Examples:

A deterministic state transition:

→ internal verification may be sufficient.

A real SwiftUI/AppKit reconstruction issue:

→ Real UI Smoke may be required.

An outside click, status-item click, keyboard route, or other external interaction that is itself the contract:

→ external UI automation must exercise that interaction when available.

Do not substitute an internal method call for an external interaction and describe them as equivalent evidence.

## Stop condition

Platform research is complete when one of the following is true:

1. sufficient evidence supports a technical direction; or
2. the remaining uncertainty is precisely identified and a minimal experiment required to resolve it is known.

Do not continue collecting sources after the decision-relevant uncertainty has been resolved.

## Output

Keep the result concise.

Preferred shape:

### Platform question
...

### Evidence
- ...

### Conclusion
...

### Engineering consequence
...

### Verification implication
...

### Remaining uncertainty
None / ...
