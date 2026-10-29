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

Attachment bytes are separate local copies owned by the same repository actor; their metadata
is stored in the event JSON. An active editor draft pins newly imported copies. Successful JSON
replacement establishes the durable references before unreferenced copies are collected; active
draft pins also prevent collection. Failed or superseded writes do not discard durable files.
File cleanup failure is reported separately from the outcome of an already committed event write.
After a successful load, abandoned imports can be collected; invalid JSON never authorizes cleanup.
The multi-file operation is not advertised as an atomic transaction with the JSON replacement.

Copies follow the event's accepted deletion and expiry rules; original files are never removed.
Attachments are not an archive and do not change the lifetime of the owning event. An explicitly
saved `keepsAfterDate` flag retains that event and its references after its date. Unchecked past
retention is handled as confirmed event deletion; ordinary Save cannot silently expire the draft.
Legacy missing flags remain false. Older versions that ignore the flag are unsafe downgrade writers
for retained events; recovery requires matched JSON and attachment copies.

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
