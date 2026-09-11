# Countdown Manager — Product

## Purpose

Countdown Manager is a native macOS menu-bar application for tracking future events by calendar day.

The product is intentionally small and quiet. The central concept is a future event date and the number of calendar days remaining until that date.

Countdown Manager is not a task manager, calendar replacement, reminder system, or notification product.

The application does not require an account or internet connection.

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

When no events exist, the popup displays an empty state and provides an action to create a new event.

## Editing and explicit actions

### Save

Save commits the current editor changes to application data.

### Cancel

Cancel explicitly abandons the current unsaved editing action.

Cancel and ordinary popup dismissal are different user actions.

### Delete

Deleting an event is an explicit destructive action and uses confirmation before removal.

### Ordinary popup dismissal

The application's main interface is presented from the macOS menu bar as a transient popup.

Ordinary transient dismissal, such as the popup becoming hidden through normal menu-bar interaction, is not Save, Cancel, or Discard.

Ordinary dismissal does not commit unsaved editor input to durable event data.

Closing and reopening the primary popup during the same application session must not reset the user's list browsing position solely because the popup became hidden.

The exact lifecycle of an active event editor or quick-subtask editor across ordinary popup dismissal is not defined here yet. If a change depends on that behaviour, resolve that specific product decision rather than inferring it from current teardown code or existing tests.

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
