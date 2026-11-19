# Countdown Manager 1.25.1 — package verification

The package was built from reviewed main source `0ef6a2a51b3f8f29c41fbd19672b6f50047ba6a2`.
The [package audit](artifact-audit.json) records the executable, ZIP and appcast hashes.
CryptoKit accepted the ZIP and exact appcast byte boundary and rejected altered payloads
and signatures. The ZIP extraction matched file bytes, modes and symlinks. Strict and
deep codesign verification passed. Bundle signing is ad hoc.

Strict SwiftLint and the [fast checks](fast.log) passed. The [native runs](native-results.txt)
used the exact extracted executable. Ten Save/Cancel cycles verified actual pixels below
the note heading, native text selection, search, width and focus changes, one subtask
reorder, and saved data. Native subtask search, reorder and release help also passed.
The [note](desktop-note-manifest.json), [mini-panel](subtask-reorder-manifest.json)
and [release help](whats-new-manifest.json) manifests identify the isolated captures.
The desktop and mini-panel README images were reviewed at their displayed sizes.

The in-process AppKit driver tests mouse event delivery and rendered views without
certifying physical keyboard input or compositor timing. Genuine update installation
belongs to the owner's manual handoff.
