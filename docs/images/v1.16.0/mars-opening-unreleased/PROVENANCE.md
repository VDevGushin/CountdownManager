# Mars opening turn — historical Dock-motion prototype, 2026-10-25

This prototype was superseded on the same date: the accepted implementation now rotates only
the status-bar Mars and keeps Dock static. These files preserve the earlier experiment.

These images belong to the earlier working-tree prototype after published 1.16.0.
They are not screenshots of the published ZIP and do not redefine that release's evidence.
The test bundle still reports 1.16.0/31; its executable SHA-256 is
`1dceba06ea0d31ffefe9e8be3b170bfd424d3db8534ca8b689ec8991d06174ea`.

`./verify.sh menu-identity-capture` passed all three native groups and produced 30 images.
Six selected images here render the running application's actual custom Dock content view,
sampled at the start, quarter turn and half turn of its real 12-second cycle. Each pose is
drawn under isolated local Aqua/DarkAqua appearances. They show the native vector planet
and the stationary Icon Composer background. They do not record the live Dock compositor.

The scenario exercises real panel/desktop opening callbacks, the advancing clock, timer
priority, restoration after a complete cycle and repeated opening. Fast checks additionally
cover the full-circle matrices, center stability, restart/stop and Reduce Motion suppression.
Strict SwiftLint passed with zero violations in 73 files. Events, preferences and logs use
the verification harness's marked isolated home; production data is not used as a fixture.

[Verification and selected image hashes](verification.json), [source input hashes](source-inputs.json)
and [native result](ui-smoke-result.txt) identify the evidence. Full local capture output and
the tested bundle remain under `.build/mars-opening-captures/`.

Still images and configured native animation parameters do not prove perceived smoothness,
physical status-item input, or the exact system Dock appearance before/after replacement.
macOS 13–25 runtime behavior and alternate system icon styles have not been exercised.
