# Countdown Manager 1.20.2 / build 38 — native release evidence

The tested production bundle was `/private/tmp/countdown-release-1.20.2-38/Countdown Manager.app`,
built through `build.sh` with the existing production public key and stable HTTPS channel.
Headers SDK 15.4, linked compatibility/deployment 13.0, `native-calendar-graphite-v2`.
Executable SHA-256: `833d5b6b66d8753a9c45935a7fea02aaea96ef09d3fdfe87cc069dcc709bb346`.

Every mode used a separately marked synthetic profile. The first five homes are under
`/private/tmp/countdown-release-1.20.2-qa/`; the final help repeat used
`/private/tmp/countdown-release-1.20.2-qa-help-resumed/whatsnew`.

| Mode | Passed result | Captures |
| --- | --- | ---: |
| desktop | 31/31 | 131 |
| general | 23/23 | 0 |
| panel | 5/5 | 31 |
| materials | 1/1 | 16 |
| attachments | 7/7 | 42 |
| whatsnew | 1/1 | 4 |

Results, original manifests, per-image hashes, source/toolchain provenance and native design
contract are under `native/<mode>/`. The modes overlap. All 224 capture hashes were checked;
representative desktop/mini and release-help dark/contrast images were inspected for this package.
Detailed family review from the earlier Graphite candidate is separately retained in
[the design QA report](../../qa/graphite-dark-theme-2026-10-29.md).

These are native synthetic fixtures, not HTML or production-user screenshots. The bundle's
`renderedAppearanceVerified=false` remains deliberate: metadata validates provenance, and the
visual review is recorded here independently. Remote NSSavePanel/Quick Look contents may not
appear in process-local bitmaps. The two warm system surfaces reported by the owner are a known
exception, not evidence that their pixels match Graphite.

[Release status, earlier failures and limits](../../releases/v1.20.2.md) ·
[Public-key artifact audit](artifact-audit.json) · [Genuine isolated update](genuine-update.json).
