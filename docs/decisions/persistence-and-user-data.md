# Persistence and user-data boundary

Status: ACCEPTED

## Context

Countdown Manager stores real user countdowns locally.

Loss, corruption or accidental mutation of that data has higher cost than failed UI polish or slower implementation.

Persistence must also remain compatible with legacy stored JSON.

## Decision

`CountdownRepository` is the production persistence boundary for countdown data.

Production filesystem work must not be moved onto the main UI actor.

In-memory state changes and asynchronous persistence must preserve revision ordering so that delayed writes cannot overwrite newer state.

Existing stored data and legacy JSON compatibility must be preserved unless the Product Owner explicitly approves a migration.

## Test isolation

Automated mutation tests must use isolated test storage.

Production:

`~/Library/Application Support/CountdownManager/countdowns.json`

must never be used as a destructive or mutation-test fixture.

Invalid production JSON must fail safely and must not be silently rewritten merely to recover from an error.

## Diagnostics

Diagnostics must not contain private event titles, notes, user emoji or subtask text.

Technical identifiers, operation type, revision and result may be logged when useful.

## Revisit

Revisit this decision only if the persistence architecture itself changes or an explicit data migration is approved.
