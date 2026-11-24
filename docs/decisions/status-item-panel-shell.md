# Anchored status-item panel shell

Status: ACCEPTED
Date: 2026-09-13
Supersedes: [Status-item popover shell](status-item-popover-shell.md), [Long-lived window shell](window-shell.md), and [Popup lifecycle architecture](popup-lifecycle.md)

## Context

Countdown Manager must match the temporary, arrowless menu-bar surfaces used by neighboring applications. It opens directly below its status item, has no title bar or traffic-light controls, cannot be dragged, hides when the user leaves it or changes Space, and only reopens after a new status-item click.

The surface contains a full SwiftUI event list and text editor, so an `NSMenu` is not an appropriate container. A public `NSPopover` supplies automatic anchoring and transient dismissal but always renders popover chrome with an arrow. The earlier retained window preserved editor, draft and scroll state but was centered and movable instead of behaving like a status-item surface.

## Decision

Use one strongly retained, borderless, key-capable `NSPanel` and one strongly retained hosting controller for the application session. The panel has transparent AppKit chrome, a shadow and rounded hosted content, no title-bar controls and no movement behavior. Starting on macOS 27, opening from the status item fades in through AppKit, and closing uses its utility-window transition when Reduce Motion is off. Other ordering paths are immediate.

On every explicit show, derive the anchor rectangle from the current `NSStatusBarButton` in screen coordinates, clamp the panel to that screen's visible frame, and place it immediately below the status item. Use `moveToActiveSpace` so making the hidden panel key moves it to the active Space instead of switching the user to an old one.

Own visibility through a synchronous requested-visible flag. Showing activates the accessory application and orders the retained panel key/front. Hiding clears the request and calls `orderOut`. Earlier systems keep the existing target-action, including its current-Space window visibility check and application-deactivation dismissal.

With the macOS 27 SDK and runtime, use `NSStatusItemExpandedInterfaceDelegate` for status-item clicks. AppKit tracks the active session, including button highlight and menu navigation. The delegate orders the same retained panel front or out. Explicit dismissal and application deactivation cancel the tracked session. When deactivation arrives during a press of this item, associate the dismissal with that press even if its session count has not advanced yet. A later key press cannot be mistaken for the closing mouse press. Direct opening from the desktop and drag hover retain their existing entry points, and older systems retain target-action.

On macOS 27.2.1, a regular foreground app can miss the expanded session's end after returning from the desktop. The failure reproduced with both a static status title and a rotating Mars. When the app first takes its persistent Dock role, it cancels the current expanded session and switches the status button to target-action. In that role the button's background follows the retained panel's visibility, independently of the glyph animation. Accessory mode retains the system session.

An acknowledged panel becoming fully occluded, application deactivation and `NSWorkspace.activeSpaceDidChangeNotification` still dismiss without checking editor, responder or key-window state. The occlusion callback covers a rapid Space transition that is visually entered and reversed before the workspace posts a completed-change notification. Returning to a Space therefore cannot restore the panel. An explicit status-item press can show it again.

Hiding changes visibility only. Do not replace the panel, hosting controller or root. The list hierarchy, editor session, draft and scroll position remain owned by the retained SwiftUI hierarchy. Save and Cancel remain the only actions that commit or abandon editor work.

Do not add mouse monitors, timing/debounce logic, frame persistence, responder restoration, window centering or alternate shells.

## Platform evidence

Apple defines `NSPanel` as a specialized `NSWindow`. `orderOut` removes a window from the screen list without making visibility own its content lifetime. `moveToActiveSpace` moves a window to the active Space when it becomes active instead of switching Spaces. `NSStatusBarButton` supplies the live positioning view whose window can convert its bounds to screen coordinates.

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [NSWindow.orderOut](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:))
- [NSWindow.AnimationBehavior](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.enum)
- [NSControl.sendAction(on:)](https://developer.apple.com/documentation/appkit/nscontrol/sendaction(on:))
- [NSButton.highlight(_:)](https://developer.apple.com/documentation/appkit/nsbutton/highlight(_:))
- [NSStatusItemExpandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitemexpandedinterfacedelegate)
- [CGEventSource.counterForEventType](https://developer.apple.com/documentation/coregraphics/cgeventsource/counterforeventtype(_:eventtype:))
- [NSWindow.CollectionBehavior.moveToActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace)
- [NSWindow.didChangeOcclusionStateNotification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification)
- [NSWindow.occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property)
- [NSWindow.convertToScreen](https://developer.apple.com/documentation/appkit/nswindow/converttoscreen(_:))

## Consequences and verification

The shell owns a small amount of native positioning logic in exchange for the required arrowless appearance and stable session lifetime. It does not expose the panel as a user-positioned utility window.

Build and in-process UI checks can verify retained panel/hosting/root identity, editor/draft continuity and deterministic toggle state. They cannot prove real status-item delivery, visual anchoring, cross-Space dismissal or the absence of unwanted restoration. Those outcomes require the short manual acceptance in `docs/VERIFICATION.md` against a provenance-identified fresh bundle. No new harness mechanism is justified.

Domain behaviour, persistence, editor controls, disclosure preferences, diagnostics, Save and Cancel remain unchanged.
