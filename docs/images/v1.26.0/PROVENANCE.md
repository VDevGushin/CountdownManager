# Countdown Manager 1.26.0 package verification

The frozen main source is `0cbe8f9de3ec0f8cd7071614541dbaae0a865ba4`.
The [package audit](artifact-audit.json) records the executable, ZIP and appcast hashes.
CryptoKit verified the ZIP and the exact signed appcast bytes. It rejected altered payloads
and altered signatures. The extracted bundle matched all 171 entries by file bytes, modes
and symlink targets. Strict and deep codesign passed. The bundle uses ad-hoc signing.

Strict SwiftLint and `verify.sh fast` passed on the combined release source. The fast gate
covered resource key completeness, CoreChecks and UIChecks, including Russian accessibility labels
for file, link and subtask matches, retained and expired events, and Unicode snippet boundaries.
The initial sandboxed run was blocked when `NSItemProvider` could not issue a temporary-file
sandbox extension. The full repeat in the logged-in macOS session passed the image-import checks.
A combined Xcode build also verified resource packaging. The extracted SwiftPM release package
contains 428 Russian interface strings and both location-purpose descriptions with matching
Info.plist fallbacks.

On macOS 27.2.1, focused in-process checks on the exact extracted bundle passed for
material and subtask search (3/3), mini-panel and status-item rendering (4/4) and release
help (1/1). Search exercises the native field editor, file and link matches in both display
modes, cleared results, selection, stable detail geometry and saved event bytes. Release help
checks automatic deferral, manual reopening from both settings surfaces and data preservation.
These runs use isolated fixtures. Physical input, VoiceOver speech and the public Sparkle
installation were outside their scope.

The [search](search-manifest.json), [mini-panel](mini-panel-manifest.json) and
[release help](whats-new-manifest.json) captures share the audited executable hash.
The two README images were inspected at display size. The search captures include filename
and URL highlighting in both appearances. Release help was inspected in both appearances
and in Increase Contrast.

The [full desktop retry](desktop-smoke-result.txt) passed all 31 scenarios on the same
extracted executable in a fresh isolated profile. The
[first run](desktop-smoke-first-attempt.txt) reached the retention flows and stopped at
the existing 65-second hard limit without an assertion failure. The rerun used no changes
to the source, bundle, assertions or timeout.
