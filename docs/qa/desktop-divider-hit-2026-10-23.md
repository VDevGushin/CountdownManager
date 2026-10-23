# Easier desktop divider capture

2026-10-23, Europe/Moscow. Acceptance snapshot on unreleased `codex/desktop-window`, recorded
before the requested branch commit/push. No release or installation in `/Applications` followed.

## Change

The existing thin `HSplitView` divider keeps its drawing, native delegate and sizing ownership.
A transparent AppKit grip adds a 12-point pointer band, resize cursor and temporary pointer
offset. Its custom mouse tracking calls the existing `NSSplitView.setPosition` rather than
forwarding synthetic events or keeping another divider ratio. Outside the band it returns nil.
Weak native discovery and resize observation are cleaned up when the view leaves its window.

Apple documents separate native effective hit rectangles, but HSplitView does not expose that
delegate as an owned application boundary. The bridge leaves it untouched. The native setter
applies existing delegate constraints: [Apple reference](https://developer.apple.com/documentation/appkit/nssplitview/setposition(_:ofdividerat:)).

## Evidence

Artifact root: `/private/tmp/countdown-divider-hit.pMCI5F`.
Executable SHA-256: `782ec9fad7c9ece0f7bea260e8768a9631f3cea1b7fb850c243bba7bd086442a`.

- Strict full SwiftLint, diff check, release CoreChecks/UIChecks and packaging: **PASS**.
- Native desktop: **PASS 15/15**, `desktop/ui-smoke-result.txt`.
- Actual root hit testing reaches the grip at center and ±5 points, at multiple heights;
  ±8-point locations pass through. Checks follow native position/layout changes.
- Prior selection, view, checklist, favorite, editor, settings, search and delete/empty retention
  assertions still pass. The minimum one-third/320-point rules remain in force.
- Independent read-only source review found no concrete blocker and required real edge dragging.
- Twenty synthetic native captures and executable provenance verified; README refreshed.
- Mini-panel **23/23** evidence reused from the earlier actions/theme build because no
  mini-panel/shared production behavior changed in this pointer-only follow-up.

## External pointer acceptance

Started the exact tested bundle with `--visual-preview --desktop-preview`, marked preview home
and synthetic saved events. Process arguments were verified before CUA attached; no production
data was used. Observed a 960-point content width in a 2× window image.

- Right-side capture, 5 points off the line, middle height: divider **639 → 559**.
- Left-side capture, 5 points off the line, upper height: **559 → 639**.
- Center capture dragged far left: **639 → 320**, preserving the left minimum.
- Right-side capture near the bottom dragged far right: **320 → 639**, preserving the right minimum.
- A coordinate mouse click on a card outside the band selected the expected event; the divider
  stayed at **639**. No control was clicked through a registry to substitute for this pointer check.

The preview then exited. Cursor assignment is verified in source; visual cursor-shape changes,
other displays/scales, real Spaces and VoiceOver are not certified by this bounded pass. Full
external XCUITest was not repeated; earlier driver limitations remain unchanged.

## Separate tooling triage

The approved HTML header mockup's cramped-padding reports were wrapper/centering false positives:
54-point toolbars already center 28-point targets with horizontal insets. A reasoned exception is
scoped only to that rule and that HTML file in `.impeccable/config.json`; no global rule or native
application verification gate was disabled. No mockup/application styling was changed for it.
