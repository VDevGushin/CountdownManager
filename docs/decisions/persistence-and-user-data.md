# Persistence and User Data

Status: ACCEPTED

## Context

Countdown Manager stores durable user-created event data locally.

Persistence operations may overlap with continued UI interaction, so an older asynchronous write must not overwrite newer accepted state.

The application also needs to preserve compatible existing user data across normal upgrades.

## Decision

`CountdownRepository` is the production filesystem boundary for countdown event data.

The repository is isolated from the main UI actor and serializes production reads and writes.

Application state coordination and filesystem serialization remain separate responsibilities:

- `Store` coordinates application-state revisions and durable snapshots;
- `CountdownRepository` performs serialized file I/O and rejects a write whose revision is older than one already accepted by the repository.

Countdown persistence uses atomic file replacement.

Existing compatible stored data remains readable unless an explicit product migration changes that contract.

A load failure caused by invalid or corrupted production data must not silently overwrite the original file as part of recovery.

## Rationale

Keeping persistence behind one repository boundary makes filesystem ownership explicit and prevents views or unrelated application code from writing production event data directly.

Revision ordering protects newer user state from delayed asynchronous writes.

Keeping application-state coordination separate from filesystem serialization allows the UI to continue operating asynchronously without moving filesystem work onto the main actor.

Backward-compatible decoding protects existing local user data during schema evolution.

## Trade-offs

Revision coordination introduces more state than direct synchronous writes.

Backward compatibility may require additional decoding logic when the stored model evolves.

These costs are accepted because silent loss or replacement of user-created data has substantially higher impact.

## Related documentation

User-visible persistence and privacy guarantees:

`docs/PRODUCT.md`

Current implementation map:

`docs/ARCHITECTURE.md`

Test isolation and persistence verification:

`docs/VERIFICATION.md`

## Revisit

Revisit this decision when:

- the persistence backend changes;
- the revision-coordination model changes materially;
- the durable data model requires an intentional incompatible migration.
