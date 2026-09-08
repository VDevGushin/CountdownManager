---
name: macos-platform-research
description: Evidence-first procedure for macOS-specific SwiftUI/AppKit behaviour when implementation architecture depends on platform behaviour.
---

# macOS Platform Research

## Purpose

Reduce architectural guessing for platform-sensitive macOS behaviour.

Use this procedure only when the technical decision materially depends on SwiftUI/AppKit/macOS behaviour.

## Typical triggers

Examples include:

- NSPopover;
- NSWindow;
- sheets and modal behaviour;
- focus and responder chain;
- keyboard interaction;
- menu-bar lifecycle;
- accessibility;
- drag and drop;
- system services;
- SwiftUI/AppKit interoperability.

Do not invoke this workflow for ordinary domain or pure business logic.

## Procedure

### 1. Define the question

State the exact platform behaviour that must be known before selecting architecture.

Separate observed behaviour from assumptions.

### 2. Gather evidence

Prefer evidence in this order:

1. Apple documentation, HIG and release notes;
2. observed behaviour on supported macOS;
3. Countdown Manager source and diagnostics;
4. official Swift/toolchain documentation;
5. stable industry practice;
6. community sources as supplementary evidence.

Community evidence does not override official platform evidence.

### 3. Assess certainty

Classify relevant statements as:

- FACT
- HYPOTHESIS
- VERIFIED
- OPEN ISSUE

Do not present an inferred platform behaviour as established fact.

### 4. Spike when necessary

If documentation and existing evidence do not resolve a lifecycle-sensitive question, prefer the smallest experiment capable of answering it.

The spike must test the uncertain platform contract, not build a production workaround.

If this procedure is being used inside a READ-ONLY review, do not create the spike. Recommend it and stop for approval.

### 5. Recommend architecture

State:

- what the evidence supports;
- remaining uncertainty;
- recommended implementation;
- rejected alternatives and why;
- minimum verification needed after implementation.

Do not build extra workaround layers around an unverified hypothesis.

Classify that minimum verification against the ladder and installed black-box trigger in `VERIFICATION.md`. When the user-visible contract depends on an external macOS interaction, the acceptance must exercise that interaction against a provenance-verified bundle; a programmatic lifecycle call or test hook may supplement it but cannot substitute for it.

## Completion

Research is complete when the architecture can be chosen from sufficient evidence or when the remaining uncertainty is explicitly identified and a minimal spike is recommended.
