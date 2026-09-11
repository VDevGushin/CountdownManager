# Countdown Manager — Product

## Purpose

Countdown Manager is a native macOS menu-bar application for tracking future events by calendar day.

The product is intentionally small and quiet. The central concept is a future event date and the number of calendar days remaining until that date.

Countdown Manager is not a task manager, calendar replacement, reminder system, or notification product.

The application does not require an account or internet connection.

## Primary interface

Accepted product contract for the next shell migration; production implementation is still pending.

The menu-bar entry opens one ordinary, long-lived application window. The application remains a menu-bar utility without a Dock icon. Launch at login starts the menu-bar entry without opening the window.

- Clicking the status item shows and activates the existing window if hidden or not key; clicking it while the window is key hides it.
- Closing the window, including the standard close command, hides the interface without quitting the application.
- Clicking outside or switching applications does not automatically hide the window.
- Hide/show preserves list browsing position, the current internal screen, an open editor and its unsaved input during the application session.
- Quit ends the session. A subsequent launch may reset transient navigation, focus and unsaved drafts. Hiding is never Save, Cancel or Discard.

There is one event editor inside the primary window. Event creation and editing, including subtask text and emoji selection, use this editor. There are no separate quick-subtask editors, action/context popovers, emoji popovers or editor sheets. Explicit controls replace these secondary flows. Primary-event selection and subtask completion remain directly available in the list.

The editor contains the existing event fields and an embedded emoji choice. Event deletion uses an explicit inline confirmation with a cancel action. Launch at login, diagnostics and Quit remain accessible through ordinary controls. A dedicated Restart action is removed; the application can be quit and launched normally.

Use a standard titled window and ordinary controls, preserving the existing typography and event hierarchy. Opening the internal editor must not reset the list underneath it. The inactive list must not receive input or remain exposed as interactive content to accessibility. Avoid popup-specific motion and forced focus transitions; respect system accessibility and Reduce Motion settings. This migration does not authorize decorative redesign or new features.

## Events

An event contains:

- a title;
- an optional note;
- a calendar date;
- one emoji;
- zero to five subtasks.

Multiple events may use the same date.

Event dates and countdowns use calendar-day semantics rather than elapsed-second calculations.

### Creating an event

A new event must use a date later than today.

Past dates and today cannot be selected as the date of a newly created event.

The first saved event becomes the primary event automatically.

Changes entered in the editor do not become event data until the user explicitly saves them.

### Editing an event

An existing event may be edited while it is scheduled for today.

An event occurring today may remain on today's date or be moved to a future date.

Editing does not change durable event data until the user explicitly saves.

### Today

An event remains active and available throughout its entire calendar date.

On that date, its countdown is represented as `Сегодня`.

The event remains editable and removable during that day.

### Expiry

After an event's calendar date has ended, the event expires automatically.

Expired events are removed rather than moved into an archive.

There is no overdue state and no automatic rollover.

Incomplete subtasks do not prevent event expiry.

## Primary event

When at least one event exists, one event is primary.

The primary event:

- appears first in the event list;
- is represented in the macOS menu bar.

The user may explicitly make another event primary.

If the primary event is deleted or expires, the nearest remaining event becomes primary.

When several eligible events have the same date, stable user order determines which becomes primary.

## Event ordering

The primary event is always displayed first.

All other events are ordered by ascending event date.

Events sharing the same date retain stable user order.

Their order must not change merely because titles or other content change.

## Subtasks

An event may contain between zero and five subtasks.

A subtask contains:

- short text;
- a completed or incomplete state.

A subtask does not have:

- its own date;
- time;
- reminder;
- priority;
- nesting.

### Completion

A subtask may be completed and later reopened.

Completed subtasks remain visible.

Incomplete subtasks are displayed before completed subtasks.

Stable user order is preserved inside each group.

Completing all subtasks does not complete, archive, or expire the parent event.

The event continues to exist until its own calendar date ends.

### Progress

When subtasks exist, the interface may show progress as completed count over total count.

When no subtasks exist, a `0/0` progress state is not shown.

### Collapse state

The subtask list may be expanded or collapsed independently for each event.

Collapse state is UI preference state rather than event content.

It is stored separately from `countdowns.json` and restored across normal application restarts.

## Menu bar

The menu bar represents only the primary event.

Its normal event representation contains:

- the event emoji;
- remaining calendar days, or `Сегодня`.

It does not display:

- event title;
- event date;
- note;
- subtask text;
- subtask completion controls;
- subtask progress.

When no events exist, the menu bar displays:

`◷ Countdown`

## Empty state

When no events exist, the main window displays an empty state and provides an action to create a new event.

## Editing and explicit actions

### Save

Save explicitly commits the current editor changes through the existing data-safety boundary. A successful Save ends the editing session and returns to the list. A failed Save keeps the editor and draft available and reports the error.

### Cancel

Cancel explicitly abandons the current unsaved editing action and returns to the list. It does not close the window. Save and Cancel retain the list's browsing context; actual data changes may affect event order according to the ordering rules above.

### Delete

Deleting an event is an explicit destructive action and requires confirmation before removal. Cancelling confirmation preserves the editor and draft. Successful deletion ends editing of that event and returns to the list; a failed deletion retains the working context and reports the error.

### Session continuity

Closing or hiding the window does not commit or discard input, dismiss the editor or reset navigation. No transient UI-state persistence is required across application restarts. The separately defined durable checklist-collapse preference is unaffected.

If an event expires while its draft is open, expiry still applies to stored data. Keep the draft visible with an explanation that the event is no longer available; disable saving it as that event. Do not silently discard the input or recreate an expired event. Cancel remains available.

## Launch at login

Countdown Manager may be configured to launch automatically when the user signs in to macOS.

Launch at login is disabled by default.

The user may enable or disable it from the application interface.

## Persistence

Countdown Manager stores event data locally on the current Mac.

The production event data location is:

`~/Library/Application Support/CountdownManager/countdowns.json`

Stored data must preserve existing supported event content across normal application restarts and compatible application updates.

Existing compatible data from older supported schema versions must remain readable unless an explicit future migration changes that contract.

Invalid or corrupted user data must fail safely.

The application must not silently overwrite invalid user data merely to recover from a read failure.

Newer successfully accepted state must not be replaced later by an older delayed persistence operation.

The technical persistence design belongs in the relevant architecture decision.

## Privacy

Countdown Manager does not require cloud storage or an online account for normal product behaviour.

User event content remains local to the Mac.

Diagnostics must not contain private event content such as:

- event titles;
- notes;
- user-selected emoji;
- subtask text.

Technical operational information may be recorded when needed for diagnostics.

## Diagnostics

Countdown Manager maintains local diagnostic information for investigating application behaviour and failures.

Diagnostics may record technical facts such as:

- operation type;
- technical identifiers;
- revision or ordering information;
- success or failure;
- UI-stall detection.

Diagnostics are not a user-content log.

## Product non-goals

Countdown Manager currently does not provide:

- user accounts;
- cloud synchronization;
- notifications;
- reminders;
- event archives;
- overdue events;
- automatic event rollover;
- independent subtask dates;
- subtask reminders;
- subtask priorities;
- nested subtasks.

These capabilities are product changes. They must not appear incidentally as part of an unrelated technical fix.
