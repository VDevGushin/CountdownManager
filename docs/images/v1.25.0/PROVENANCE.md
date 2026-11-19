# Countdown Manager 1.25.0 — package verification

The package was built from reviewed main source `2de49901de9d89dae9a95a9d4ded98e9ada6ab58`.
The [package audit](artifact-audit.json) records the executable, ZIP and feed hashes.
The Release build used pinned Sparkle 2.10.0 and the native design contract.

- CryptoKit verified the archive and exact raw feed boundary using the bundled production public key.
  It rejected changed archive and feed payloads and changed signatures. The feed's embedded notes,
  version, minimum system, architecture and archive size matched the release.
- Extracted ZIP entries matched the original bundle in bytes, modes and symlinks.
  Strict and deep codesign verification passed.
- Strict SwiftLint and the [fast checks](fast.log) passed on the release source.
- The [native results](native-results.txt) are from the extracted executable. They cover reorder,
  editor order, completion, the combined mutation chain including deletion, transfer, copy, search
  and release help. The [reorder](subtask-reorder-manifest.json),
  [completion](subtask-completion-manifest.json) and [release help](whats-new-manifest.json)
  manifests identify the synthetic captures and exact executable.

The README images were inspected at their displayed sizes. These isolated AppKit runs
exercise native paths and repository state. Physical Tab/Space activation and changing the
system Reduce Motion setting remained outside this release run. App signing is ad hoc.
