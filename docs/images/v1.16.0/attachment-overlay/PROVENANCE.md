# Countdown Manager 1.16.0 / build 31 — attachment overlay and mini navigation

Date: 2026-10-25, Europe/Moscow. Status: **PREPARED LOCALLY / NOT PUBLISHED**.
This follow-up replaces the prepared [priority/limit candidate](../priority-limit/PROVENANCE.md).
Historical captures and results remain in their original directories.

## Exact bundle and captures

Version **1.16.0**, build **31**, identifier `local.countdownmanager.app`, arm64.
Executable SHA-256: `5836d97009081e079e3414f66359d602d4bad58624fd76413d7496e4448ed001`.
Local evidence root: `/private/tmp/countdown-attachment-overlay.YbsaYR/`.
The candidate is `candidate/Countdown Manager.app` beneath that root.

[manifest.json](manifest.json) records **17 selected native PNGs**, dimensions, appearance
metadata and SHA-256 values. They cover desktop and mini libraries with all/search/empty
states, desktop missing-copy errors, and the unchanged desktop Settings dismissal reference.
Source manifest SHA-256: `804b7f33370cac1daa07e20063b19c2d2fbf68798c87114de1d461ae061ec359`.
All captures use isolated synthetic events, files and forecasts. The method is
`NSView.cacheDisplay`: in-process native rendering, not a compositor screenshot or physical-input evidence.

Desktop shows `Вложение` at left and a close cross at right, with no Back/count in its header.
Mini keeps `Вложения` and a plain left-chevron Back matching Settings, also without a header count.
Both use `Файлов: N` before searching and `Найдено: X из N` for a nonempty trimmed query.

## Fresh native acceptance

Strict SwiftLint passed with **0 violations in 70 files**; CoreChecks/UIChecks passed.
Fresh exact-bundle Aqua acceptance passed desktop **27/27** (44.379 seconds) and mini **23/23**
(28.023 seconds). Both routes exited 0 without a main-thread stall; before/after hashes match
the executable above. Desktop includes the shared library scenarios on both surfaces:
close/reopen, backdrop/pane input boundaries, selection/divider retention, owner removal,
search/clear/no-results, 44/36-point previews and the new header/footer count semantics.
These are new exact-bundle results; older priority/limit results are separately identified.

The documentation reviewer visually inspected `desktop-attachment-library-all-dark.png`
and `panel-attachment-library-all-light.png`. The new headers, close/Back controls and
footer count are visible without an actionable layout defect in those images.

## External interaction acceptance

[external-acceptance.json](external-acceptance.json) records CUA native app interaction with
an isolated synthetic probe. Its unsigned executable is byte-identical to the production
candidate above; the probe uses a separate identifier and synthetic home.

Desktop checks passed: an empty inside click leaves the library open; an outside pointer
click over a different event card closes it without selecting that card; Escape from a focused
nonempty search and the cross each close it. Underlying controls are absent from the accessibility
tree while the overlay is present. Mini checks passed: the Settings-style Back chevron,
no header count, numeric search yielding `Найдено: 1 из 15`, Clear restoring `Файлов: 15`,
and Back returning to events. The probe was quit after the check.

The first preview fixture was dated October 24 and expired normally on October 25; it was
stopped and only synthetic dates were reseeded before acceptance. A diff-only accessibility
response was initially read as empty; the full tree established that the inside click retained
the pane. Those observations are retained in the receipt, not presented as product failures.
English-layout external typing used numeric `15`; exact Russian filename queries are covered
by native regression. These interactions do not constitute full VoiceOver or first-install acceptance.

[acceptance.json](acceptance.json) combines the exact-bundle native, external and artifact receipts.

## Local signed-artifact audit

[artifact-audit.json](artifact-audit.json) records a public-key-only Apple CryptoKit audit:

- ZIP `CountdownManager-1.16.0-31.zip`: **5,778,958 bytes**, SHA-256
  `3eca26a65657bda0c905fcb96ee2189e0ffc22fdc295db9dd08c642254422259`.
- Signed appcast SHA-256: `21e3a0311711b72507f6f7d0415d5e59229e8a77c7ae5f852e8b4aa2652d0494`.
- Both signatures pass; damaged messages and signatures are rejected.
- Production key/channel match the baseline; no test flags or loopback exemptions.
- Extracted strict/deep codesign passes; all **166** entries, symlinks and modes match the candidate.

The auditor did not access the private key or publish artifacts. These prepared files do not
prove public download availability, first installation or production update acceptance.

## Reused evidence and limits

The [priority/limit receipt](../priority-limit/acceptance.json) and older RC1/RC2 receipts identify
their own executable origins. Updater, storage and external media opening evidence is reused
only for unchanged routes; it is not a new update/default-app-opening run on this executable.
Cold first-launch default-app opening, forced mid-copy cancellation, older macOS, Intel,
first-install Gatekeeper and full VoiceOver speech remain uncertified. Isolated in-process
actions and renders alone do not establish physical pointer or keyboard acceptance.
