# Desktop update restart — 2026-10-29

Status: correction included in published **1.20.1/build37**. Exact-package acceptance, signed
artifact audit and anonymous delivery passed; no local installation by this task. The installed
1.20.0/build36 is left untouched for the user to update.
[Publication receipt](../images/v1.20.1/publication.json).
Branch: `codex/desktop-update-restart`. See [patch status](../releases/v1.20.1.md).

## Report and observed production sequence

The user reported that Check for Updates from desktop Settings downloaded the update, but
Restart and Install appeared to do nothing. They confirmed that repeating through the mini-panel
completed the update. Read-only inspection found the installed app at 1.20.0/build36 afterward.
The prior updater implementation is identical between tags 1.19.0 and 1.20.0.

Filtered local diagnostics recorded installation starting at16:14:16 Moscow, desktop Settings
dismissal at16:14:27, desktop close at16:14:29 and automatic termination/relaunch at16:14:30–31.
There was no application restart-safety cancellation, postponed install or updater abort in between.
No production process or event data was used as a mutable fixture during investigation.

## Mechanism

Apple documents that [`NSWindow.preventsApplicationTerminationWhenModal`](https://developer.apple.com/documentation/appkit/nswindow/preventsapplicationterminationwhenmodal)
defaults to true and can prevent termination before the application delegate is consulted.
Sparkle 2.10 `InstallerProgressAppController.sendTerminationSignal` sends the ordinary quit request
through `NSRunningApplication.terminate`. Desktop Settings is a native SwiftUI sheet; mini Settings
is internal content without a native sheet.

Four standalone native controls used real SwiftUI sheets with interactive dismissal disabled,
SDK 15.4 and the current macOS runtime. Both direct NSApp termination and the Apple quit event
were blocked without a delegate call at the default true flag. Changing only the sheet flag to
false delivered `applicationShouldTerminate` and `applicationWillTerminate`.
[Probe source and logs](desktop-update-restart-2026-10-29/main.swift),
[blocked Apple event](desktop-update-restart-2026-10-29/default-appleevent.log),
[allowed Apple event](desktop-update-restart-2026-10-29/allow-appleevent.log).

## Correction

A transparent, noninteractive window-local bridge configures only the owned desktop sheet.
Settings and read-only attachment screens do not prevent the updater's quit event. Event editors
and text composers retain native protection. The property is applied on attachment and each value
update; no global window scan, timer, closing/reopening coordinator or updater bypass is introduced.
The authoritative application guards for edits, writes/recovery, timer and diagnostic export are unchanged.

## Verification

- Full SwiftLint: 0 violations in 90 files.
- Fast CoreChecks/UIChecks and native design source/build gates passed.
- Independent implementation review found no blocking issue.
- Native desktop policy regressions: final **31/31 PASS** on a fresh isolated home. The first run
  stopped after 5 scenarios when the active Space changed and the input sheet lost key status; this
  failed attempt is preserved separately, not included in the successful total.
- Genuine isolated Sparkle update while desktop Settings remains open: **PASS**, build 20120→20121,
  PID 69323→69549 with one automatically relaunched host. No Settings/desktop close or app reopen
  was performed after the final Install click. Exact JSON, IDs/primary, owned TXT/PDF, ownership
  markers, original files and selected preferences were preserved.
- Discovery began with a scheduled check at fixture startup; ordinary Check for Updates in desktop
  Settings then refocused that update. The download and final Install occurred with the Settings
  sheet still attached. The receipt does not claim a separate fresh manual-discovery run.
- Installer start was logged at 13:43:30.628Z; termination at 13:43:30.704Z, and new launch at
  13:43:30.964Z. Sheet dismissal occurred after install started, as part of termination.
- [Native result](desktop-update-restart-2026-10-29/native-result.txt),
  [first focus failure](desktop-update-restart-2026-10-29/native-first-focus-failure.txt),
  [genuine observer](desktop-update-restart-2026-10-29/genuine-update.json),
  [filtered lifecycle](desktop-update-restart-2026-10-29/genuine-update-filtered.log),
  [combined receipt](desktop-update-restart-2026-10-29/receipt.json).

Native property checks establish wiring, not installation. The genuine update must independently
observe replacement and automatic relaunch without reopening/reacquiring the app after Install.
The new-session Sparkle code 1001 means no newer update; it is not an installation failure.
The earlier production update observation belongs to the user's workaround, not to this correction.
The termination-policy correction leaves the existing UI appearance unchanged. The patch also
updates release-help text/ID; fresh exact-package screenshots and **32/32** native acceptance are
recorded in the [patch provenance](../images/v1.20.1/PROVENANCE.md).

## Cleanup

Completed the user's cleanup request after preserving the diagnostic and acceptance evidence.
Moved 69 scoped temporary items, containing 44 verified Countdown application copies and approximately
2.86 GiB of builds/logs/fixtures, to a recoverable Trash folder. The restoration manifest records
every original and destination path. Exact known-path moves/readback were verified; macOS denied
listing the Trash parent, so no unrelated Trash contents were inspected.

The installed application executable and protected source files were hashed before and after and
were unchanged. Production data was not moved. Prior shared Sparkle-test defaults were restored;
new isolated profiles were exported before removal. The local HTTP test server and completed
Lavish server were stopped. Accepted HTML design, repository source/history, release screenshots,
production data, production preferences and Keychain were preserved. The normal installed app was
opened again, without installing this correction.

[Cleanup receipt](desktop-update-restart-2026-10-29/cleanup.json) contains the actual restore-manifest
location. The seed and observer scripts remain alongside the durable receipt. Trash was not emptied.
