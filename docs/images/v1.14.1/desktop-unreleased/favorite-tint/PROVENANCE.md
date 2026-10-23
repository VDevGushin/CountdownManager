# Desktop favorite action color

2026-10-24, unreleased `codex/desktop-window`, package 1.14.1/29, not the published release.

Source: `/private/tmp/countdown-favorite-tint/native-final-pass/Captures`.
Release executable SHA-256: `4df138f9b8f7c64b70912e57722898312032c4f063fb0f1f9d378626426174f7`.
The 64 current synthetic PNGs, exact manifest and PASS 22/22 result are retained. Main README images
are refreshed from this run; historical images and the preceding checklist recording are preserved.

The only production change makes the desktop outline star use primary ink, matching pencil and
trash. The filled favorite star keeps accent tint. Mini-panel code and behavior are unchanged.
Root visually inspected selected/unselected favorites in Dark and Light. Native regression checks
also inspect the rendered three-icon regions in all four combinations. They use the native split
pane's converted coordinates and tolerate display-profile color conversion, rather than assuming
SwiftUI control-local geometry is window-global or asserting exact cross-display RGB equivalence.

Strict SwiftLint, UIChecks and packaging passed. The final native desktop run passed 22/22.
Existing CoreChecks and mini-panel 23/23 evidence are reused because those production inputs did
not change. No new external-input or compositor-motion claim is made for this static color fix.

Earlier palette-test iterations failed because of the initial color tolerance and control-local
coordinates; only the test probe was corrected, not the intended UI palette. A subsequent run
passed all palette checks but encountered the previously documented panel activation/occlusion
failure after ten scenarios. The unchanged final bundle then passed the complete native run;
that earlier failure remains separately under `native-verified/`, not counted as a successful run.

No commit, push, merge, release or `/Applications` installation is part of this task.

The tested package replaced only `.local-apps/Countdown Manager.app` after the user confirmed Quit.
The previous working bundle is privately archived under `/private/tmp/countdown-favorite-tint/private-backup/`.
Signature and executable hash were verified; the launched process originates from that working
path. Production event JSON remained byte-for-byte unchanged before and after normal launch.
