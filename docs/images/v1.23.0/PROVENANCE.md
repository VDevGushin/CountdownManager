# Countdown Manager 1.23.0 — exact package evidence

Release source is `54167e7d5c7fbb5698417d2ba3c3b6822edafcdf` on clean main. Version/build is 1.23.0/45.
The final package passed independent public-key and native acceptance on isolated data.

## Package

- Archive SHA-256 `1e2c3c95dffe0af78b66ebc8582bf9ef91f5006b643c71bb84075f7250663e77`, 6717542 bytes.
- Feed SHA-256 `00826f144d6cca59d1a306e55923aebe87c4d986808698dac69a2d5c1769892e`, 3613 bytes.
- Executable SHA-256 `f3ceb83291dcadbccdcc9823e0e925b215c5e0234134392ea99af87943d0e33d`.
- The existing named production Sparkle key was used. CryptoKit independently accepted
  archive/feed signatures and rejected four payload/signature mutations.
- Feed signed byte boundary, metadata, embedded notes, extraction bytes/modes/symlinks
  and strict/deep codesign passed in [artifact-audit.json](artifact-audit.json).

## Exact native acceptance

- [Transfer](transfer-native-result.txt) passed on the final production executable.
- [Release help](help-native-result.txt) passed first-safe opening, deferral, one-time
  presentation, manual reopening, Escape and unchanged event/timer state.
- [Transfer manifest](transfer-manifest.json) and [help manifest](help-manifest.json)
  record executable provenance and real native Light/Dark/Increase Contrast captures.
- Three README images and the new release-help layout were visually inspected.
- [Full fast checks](fast.log) passed for the frozen release source.

Development evidence in [the readiness report](../v1.22.0/subtask-transfer-unreleased/RELEASE_READINESS.md)
includes 14/14 broader native groups, data stress tests and direct keyboard acceptance.
External XCUITest automation-mode authentication and VoiceOver/controlled physical Spaces
limitations remain as documented there. Ad-hoc bundle signing and Sparkle authenticity
are distinct from Apple notarization.
