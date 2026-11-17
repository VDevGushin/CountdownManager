# Countdown Manager 1.24.0 — package verification

Release source is `3d01a67ace806098cbe8e82c4a3256bd47546d81` on clean main.
The [package audit](artifact-audit.json) records the executable, ZIP and feed hashes.
The canonical Release build used the pinned Sparkle 2.10.0 and native style contract.

- The production key's existing public fingerprint matched the built application.
  CryptoKit independently accepted both Ed25519 signatures and rejected four changes
  to payloads or signatures. The signed raw feed boundary and embedded notes matched.
- Extracted ZIP entries matched the original bundle in bytes, modes and symlinks.
  Strict and deep codesign verification passed.
- [Fast checks](fast.log) and strict SwiftLint passed for the release source.
- [Search](search-native-result.txt) passed 2/2 groups on the extracted executable.
  The [search manifest](search-manifest.json) identifies native screenshots and hashes.
- [What’s New](help-native-result.txt) passed 1/1 group on repeat with the same executable.
  The [first attempt](help-first-attempt.txt) timed out after the app resigned active
  during the return from release help to mini Settings. The retry passed that step.
  The [help manifest](help-manifest.json) identifies the four appearance captures.

The desktop README screenshots were inspected at their displayed scale.
Native captures use isolated data and AppKit rendering. Physical keyboard delivery,
VoiceOver speech and compositor timing remain outside their scope. Bundle signing is ad hoc.
