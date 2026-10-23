# Full regression — current native capture provenance

Date: 2026-10-23, Europe/Moscow. Unreleased `codex/desktop-window`, bundle still 1.14.1/29.
These are not screenshots of the published mini-app release.

- Desktop source: `/private/tmp/countdown-full-regression.SBufkW/final/native/desktop/Captures`.
- Desktop executable SHA-256: `c075d9f0b50ab280b9951e4b0317455682107c5604e207765e19da1fbccdf0a8`.
- Native desktop result: PASS 10/10; ten PNGs and exact manifest are retained here.
- The mixed-checklist Light/Dark frames show unfinished rows above completed rows; native
  reopening/order/UUID assertions and external checkbox interaction passed. Stored order is unchanged.
- Filtered creation Save/Cancel and shared-panel visibility are additionally exercised by the run.
- Weather source: `/private/tmp/countdown-full-regression.SBufkW/weather-current/native/Captures`.
- Weather executable SHA-256: `11893c86715f3507f5a536309f00b4da8d8cbabc3e0836e4af133777672bff90`.
- Weather result: PASS 5/5, ten PNGs and manifest under `weather/`. Difference from the desktop
  bundle is only the corrected weather test geometry; no product UI change follows desktop capture.
- PNGs are native AppKit frame renders at 2× with synthetic events/preferences/forecasts.
  They do not prove physical Dock/Spaces, live weather, VoiceOver or external Save-dialog completion.
- Main mixed Light capture was visually inspected. Other native suites apply their documented
  layout/state assertions; generated screenshot counts are not a claim of exhaustive visual review.
- Earlier release/branch captures are preserved. Production data and installed app are untouched.
- Overall regression is not fully green; see the [campaign report](../../../../qa/desktop-regression-2026-10-23.md)
  for raw-run provenance, historical failures, accepted retests and remaining external/manual limits.
