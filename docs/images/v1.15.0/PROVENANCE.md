# Countdown Manager 1.15.0 / build 30 — candidate evidence

Status: signed production candidate; final external and actual update acceptance passed, publication pending.

The 64 synthetic native PNGs and exact manifest come from
`/private/tmp/countdown-1.15.0-rc/native-desktop/Captures`, using the actual production-configured
candidate, not a development updater-disabled package. Executable SHA-256:
`d7486a2ac7f394b794cad2463bce60a4ff261e9e80e23a0eb4eae9e2dd4eb25d`.
The package embeds the existing public key and stable HTTPS channel. Runtime fixtures isolate
event data, preferences, forecasts, accessibility overrides and service side effects; settings
service controls in synthetic captures need not reflect an ordinary live update session.

The exact candidate passed desktop 22/22, mini-panel 23/23 and editor workflows 5/5. Result files
are retained here. Still images are NSView cache-display renders, not compositor-motion proof.
The preceding desktop checklist recording remains historical evidence for the unchanged row
animation; it is not relabeled as a newly recorded 1.15.0 video. Historical release images remain.

`package-audit.json` independently verifies production ZIP/feed signatures using only the public
key, including damaged-message/signature rejection, strict/deep codesign after extraction and all
166 file/symlink/mode entries matching the accepted candidate. It is not proof of public hosting
or actual updater replacement/relaunch. Separate `actual-update.json` records a real older/newer
test-copy Sparkle transition with automatic relaunch, unchanged synthetic JSON and checklist
preference. The older shell's auto-hide was suppressed by a supported test flag; the newer host
launched normally with embedded isolation. `preflight-input-diagnostics.json` records the final
ABC Latin-input and genuine native diagnostic Save PASS 2/2. Detailed limits belong in
`docs/releases/v1.15.0.md`.
