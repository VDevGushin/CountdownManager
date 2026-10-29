# Native Graphite captures — working tree, 29 October 2026

These captures show an **unreleased working-tree change** over version 1.20.1 / build 37.
They do not replace historical captures of the published 1.20.1 package.

All runtime modes used the same `build.sh` release-path bundle:
`/private/tmp/Countdown Graphite Validation.app`. Actual compiler SDK: macOS 15.4;
deployment and linked compatibility: 13.0; design contract: `native-calendar-graphite-v2`.
The bundle is ad-hoc signed and update delivery is disabled. It was not installed in Applications.
The captured views use synthetic isolated data, preferences, weather and files.

Each subdirectory contains the original native capture manifest, per-PNG SHA-256 hashes,
`ui-smoke-result.txt`, `NativeBuildProvenance.json` and `NativeDesignContract.json`.
`general` has no PNGs. The build metadata deliberately says `renderedAppearanceVerified=false`:
it certifies source/toolchain provenance, while visual review is separately recorded in the
[QA report](../../../qa/graphite-dark-theme-2026-10-29.md).

| Runtime | Result | Generated PNGs |
| --- | --- | ---: |
| desktop | 31/31 | 131 |
| general | 23/23 | 0 |
| panel | 5/5 | 31 |
| materials | 1/1 | 16 |
| attachments | 7/7 | 42 |
| whatsnew | 1/1 | 4 |

The 224 PNGs include overlapping fixtures and intermediate frames. Only the representative
set listed in the QA report was visually reviewed. `desktop/desktop-diagnostics-dialog-dark.png`
contains only the remote system dialog's uniform background and is **not** a picture of its
controls. Some embedded Quick Look document pixels are also unavailable through in-process
bitmap caching. These captures establish the application's enclosing surfaces; runtime assertions
separately establish native appearance/ownership and renderer identity.
