# Embedded attachment quick preview

Status: ACCEPTED
Date: 2026-10-26

## Context

Saved attachments need a large preview and adjacent-file navigation while preserving the event,
library query and scroll position. The desktop already owns a single native sheet and the
mini-panel retains its internal hierarchy through hide/show. Saved files and their expiry remain
owned by the existing Store/repository.

## Decision

Embed `QLPreviewView(.normal)` inside the existing attachment presentation. Countdown owns the
filename, derived position, navigation and explicit external-open button. Each surface owns one
transient identity-based preview session; no second saved collection or preview archive is added.
The previous/next controls also own unmodified Left/Right keyboard shortcuts, using the same
session navigation as clicks. Keyboard browsing spans the full saved event order, including
when the retained source library has a search query, and stops at each end.
The library stays mounted with its original dimensions while inactive. Separate accessibility
containers distinguish the active screen from retained hidden content.

Resolve only validated repository-owned file URLs. Cancel outstanding work and reject obsolete
generations on navigation, close or reopen, including reopening the same attachment UUID.
Normal desktop dismissal preserves the visible content and geometry until native `onDismiss`;
invalidating an owner immediately releases its renderer. The event lifetime is never extended.

Set `autostarts = false` and `shouldCloseWithWindow = false`. Explicitly close and discard each
renderer on selection replacement, dismantling, its actual window hiding or closing. Create a
new renderer on show; a closed `QLPreviewView` cannot be reused. A window-local KVO observation
of `isVisible`, with `willClose`, owns this resource boundary. It does not own application/window
visibility, introduce a timer or change the accepted panel shell.

The host API has no public content-ready/error callback. A resolved URL and live renderer mean
that preview was requested; successful photo/PDF/movie rendering needs actual visual evidence.
Existing unsupported files use the native fallback; a missing URL has an explicit application
state with navigation still available.

## Evidence and limits

Apple documents asynchronous item loading, irreversible `close()`, the explicit cleanup
obligation when `shouldCloseWithWindow` is false and the movie-autoplay setting:
[QLPreviewView](https://developer.apple.com/documentation/quicklookui/qlpreviewview),
[close](https://developer.apple.com/documentation/quicklookui/qlpreviewview/close()),
[shouldCloseWithWindow](https://developer.apple.com/documentation/quicklookui/qlpreviewview/shouldclosewithwindow),
[autostarts](https://developer.apple.com/documentation/quicklookui/qlpreviewview/autostarts).

Isolated probes on macOS 26.6.2 / 25G83 / arm64 showed that an already occluded window can
show/hide without an occlusion-state change. An occlusion-only observer therefore cannot own
renderer cleanup. Window visibility KVO observed show/hide/reopen/close. The exact native host
probe verified one renderer on show, zero on hide, a distinct non-autostart renderer on reopen,
and `previewItem == nil` on the strongly retained old renderer after hide/close/shutdown.
These probes establish the public resource boundary on that runtime, not playback behavior for
every provider or execution on macOS 13. Integrated acceptance follows
[the verification map](../VERIFICATION.md#attachment-shelf-and-embedded-quick-preview).
