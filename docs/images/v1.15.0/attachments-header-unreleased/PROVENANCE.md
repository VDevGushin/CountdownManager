# Attachments and inline desktop header — working-source evidence

Date: 2026-10-24. Status: **unreleased working source**, based on repository revision
`39b4734`. This is not a new public release and does not replace the published 1.15.0 images.

The isolated release bundle retains version **1.15.0 / build 30** and has its updater disabled.
Its executable SHA-256 is
`e5a6e47d558c5fc1f59dba1ab57741eaf33968faee371dd002bb92a4bd4a5d1b`.
`manifest.json` records that executable, native appearance, dimensions, scale and the seven
selected captures. The source-input digest and acceptance boundaries are in `acceptance.json`.
The retained bundle is `/private/tmp/countdown-header-weather.4egrXD/Release Countdown Manager.app`.

The current bundle was built with the ordinary `build.sh` staging flow into this temporary
location, not into `/Applications`. Final strict SwiftLint reported zero violations;
CoreChecks and UIChecks passed against the same retained release build directory. The equivalent
direct SwiftPM checks reuse its compiled code; no production event data or preferences are fixtures.
The deterministic eval-runner suite separately passed **33/33**, including the real Core oracle
after the new Core source files were added.

Native results from the exact retained release bundle:

- desktop: **24/24**, including shared attachment rows, editor Cancel/Save, owned-copy deletion,
  original-file preservation and the inline date/weather geometry;
- mini-panel: **23/23**;
- editor workflows: **5/5**;
- collapse regression: **2/2**;
- three independent continuity runs: **8/8** each.

Each route used a separate marked temporary home, event JSON, defaults and diagnostic logs.
The selected images are native `NSView.cacheDisplay` renders with synthetic events/files and
forecasts. They are not compositor-motion recordings, real weather or native geolocation evidence.
Published-version images and earlier motion recordings were preserved.

The focused external XCUITest
`testAttachmentsNativePickerSaveCancelAndSharedSurfaces` passed **1/1** in a separately built
Debug test copy. It exercised the real open sheet, Cancel/reopen, ordinary typed path selection,
draft import and Cancel cleanup, repeat import and Save, metadata and copied bytes, shared
desktop/mini-panel presentation, removal Cancel then Save, and unchanged original bytes.
The user selected an English input source; its exact source ID is not logged. No clipboard
fallback, global input-source change or substituted native OK action was used.

Earlier failed runs are retained in the temporary evidence directory: a Russian-layout path
synthesis failure, incomplete test-field clearing, and container identifiers overriding child
actions. The final scenario uses ordinary Select All/Delete/typing, verifies the exact path and
keeps its original file assertions. Native measurement failures were addressed by fixture
namespaces and live native header/date/weather frames, without relaxing geometry assertions.

The raw `.xcresult` and its screenshots remain in the temporary evidence directory. They are
not copied here because macOS test captures can include other personal desktop content.
This folder contains only native renders of isolated application windows and compact result data.

Opening copies in third-party applications, playback/codecs, very large media performance,
every filesystem interruption, physical status-item/Spaces behavior and full VoiceOver acceptance
are not established by these results. The feature uses explicit default-application opening;
the external test verifies the saved-file action's presence, not another application's behavior.
