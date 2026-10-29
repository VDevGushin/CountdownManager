# Retained events implementation captures — 2026-10-29

These eight images show the current native SwiftUI/AppKit implementation with isolated synthetic
events and copied files. They are not HTML mockups or screenshots of the published release.
The candidate retains version 1.18.1/build 34; no version bump,
installation or publication was performed.

Executable SHA-256: `224cfc19524519cfd81060882a04db1352d8915cc57d06f9c0a889980a6e6f5e`. The retained tested bundle was hashed and matched the native
capture manifest. PNG hashes and appearance/capture metadata are in [manifest.json](manifest.json).
The complete native run passed [29/29 scenarios](ui-smoke-result.txt), including calendar expiry,
retention, both list modes, mini, editor Save/Cancel and confirmed owned-file deletion.

Capture method: `NSView.cacheDisplay`, in-process rendering of native windows/sheets. The feed
mode was checked for full-width rows and three stable document-height observations before theme
captures. These are settled-state evidence, not a physical compositor recording or proof of no flicker.

Full generated captures and tested bundles are preserved under `/private/tmp/countdown-retention-full-evidence/`;
only feature-relevant images are retained here. Historical published release screenshots are unchanged.
See [verification report](../../../qa/retained-events-2026-10-29.md) for failed attempts, external UI
fallback and remaining automation limits.
