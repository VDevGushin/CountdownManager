# Countdown Manager — Product

## Purpose

Countdown Manager is a native macOS menu-bar application for tracking future events by calendar day.

The product is intentionally small and quiet. The central concept is a future event date and the number of calendar days remaining until that date. The application also provides one lightweight countdown timer for short time-based reminders.

Countdown Manager is not a task manager or calendar replacement. Outside the single timer completion alert, it does not provide event or subtask reminder workflows.

The application does not require an account or internet connection.

## Primary interface

Accepted product contract for the menu-bar panel shell.

The menu-bar entry opens a temporary panel anchored directly below the status item. The application remains a menu-bar utility without a Dock icon. Launch at login starts the menu-bar entry without opening the panel.

- Clicking the status item shows the panel from that status item on the current active macOS Space if hidden; clicking it while visible hides it. Every distinct click determines the next visible/hidden state even when clicks are rapid.
- The panel has no arrow, title bar or traffic-light controls. It is not draggable and never behaves as a centered or independently positioned utility window.
- Closing the panel, including through the standard close command, hides the interface without quitting the application.
- When the user leaves the panel, including switching to another application or Space, it automatically hides. Returning to the original Space does not show it again; only a new status-item click does.
- Hide/show preserves list browsing position, the current internal screen, an open editor and its unsaved input during the application session.
- Automatic hiding, the close command and the status-item toggle never mean Save, Cancel or Discard. Quit ends the editing session, while an active timer continues according to its persisted deadline.

The single timer is shown as a compact strip above the event interface. There is one event editor inside the primary panel. Event creation and editing, including subtask text and emoji selection, use this editor. There are no separate quick-subtask editors, action/context popovers, application-owned emoji popovers or editor sheets. Explicit controls replace these secondary flows. Primary-event selection and subtask completion remain directly available in the list.

The editor groups title, optional note and date together, with separate subtle blocks for the additional emoji and subtasks. Blocks use 12-point inner spacing, 8-point corners and 12-point separation. The menu-bar favorite choice is separated below these groups. The timer strip and fixed Save/Cancel action area keep their existing responsibilities; the form scrolls within the panel.

The additional emoji is a single full-width selection control labelled `Значок · необязательно`. It displays `Без значка` or the selected emoji, with a disclosure chevron at the right edge. A separate small clear button appears inside the same visual field only when an emoji is selected; clearing must not also open the picker. The field is a selection control, not an editable text input. The picker is initially collapsed. Activating the field reveals eight compact presets and a `Все значки` action; activating it again collapses the picker. Opening or closing it preserves every draft field.

`Все значки` reveals the larger inline catalog organized into five named sets: `Общие`, `Дети`, `Работа`, `Транспорт` and `Праздники`. Each set is a six-row/eight-column page, fitting the editor's available inner width. The current set name is shown above conventional previous/next controls with page dots; horizontal drag/swipe may also change sets. The first set keeps the compact presets as its top row. Choosing any emoji or clearing the selection resets catalog navigation and collapses the entire picker. New selections come from the provided catalog; an existing stored valid emoji outside that catalog remains displayable and may be preserved until the user selects another one.

Picker disclosure uses a 200-millisecond non-spring height and opacity transition. The chevron communicates expansion, and changing the selected value may use a brief opacity transition. With Reduce Motion enabled, transitions are immediate. Rapid repeated requests finish in the state requested by the last action. Collapsed picker content does not receive input or remain exposed as interactive accessibility content.

Event deletion uses an explicit inline confirmation with a cancel action. Launch at login, diagnostics and Quit remain accessible through ordinary controls. A dedicated Restart action is removed; the application can be quit and launched normally.

Use ordinary controls inside the panel. The event interface uses a warm ivory palette with a terracotta accent and serif titles, with a related warm dark appearance and an Increase Contrast adaptation. The featured event has a larger calendar leaf on its right; other events have smaller calendar leaves on their left. The featured event is the selected favorite, or the nearest event starting with today when no favorite is selected. Each leaf shows the event's actual month and day, without a leading zero. A selected additional emoji appears immediately before the favorite star. Empty emoji and legacy `📅` are omitted from the list because the leaf already conveys the date; legacy stored values remain available in the editor. When no favorite is selected, the featured block is labelled `Ближайшее событие` and every star is unfilled.

Each event and its checklist form one visually separate block on a subtle surface, with space between events. Individual subtask rows have no horizontal separators. Completed subtasks remain readable and directly reopenable, with quieter text and neutral completion marks.

Opening the internal editor must not reset the list underneath it. The inactive list must not receive input or remain exposed as interactive content to accessibility. Use simple native state-change animation for primary selection and subtask completion; avoid custom panel motion and forced focus transitions, and respect system accessibility and Reduce Motion settings.

## Timer

Countdown Manager exposes exactly one timer.

The timer has no user-editable name or task text. Its visual identity is simply `⏰`.

When idle, the user chooses one of seven fixed durations: `5`, `10`, `15`, `30`, `40`, `60`, or `120` minutes, then starts the timer. There is no custom-duration input.

While running:

- the interface shows `⏰` and the remaining time;
- there is no Pause action;
- the duration cannot be edited or extended;
- the only timer action is Delete.

Deleting the timer clears it immediately and dismisses any visible completion alert.

The timer uses an absolute deadline rather than decrementing persisted seconds. Closing or hiding the panel, quitting and relaunching the app, system sleep, and ordinary clock ticking do not reset the timer. Time elapsed while the app is not visible still counts.

When the deadline is reached while Countdown Manager is running, the timer enters a finished state that shows `⏰ Время вышло` until the user deletes it. The application also plays its bundled completion sound and presents its own non-activating completion alert above other windows for five seconds. The alert uses the application's shared warm palette: an ivory surface and terracotta alarm accent in Light appearance, with the related warm surface and accent in Dark appearance. Text, border and accent adapt to Increase Contrast; a reused alert follows appearance changes. Clicking anywhere on the alert dismisses it immediately without activating Countdown Manager or changing the finished timer state; without a click, it hides automatically after five seconds. While the timer runs, its menu-bar representation breathes with a gentle pulse. The finished menu-bar alarm keeps rocking from foot to foot, like a ringing mechanical alarm clock hopping on the surface it stands on, until the user deletes the finished timer; with Reduce Motion enabled, it pulses instead. This alert does not depend on macOS notification permission.

Countdown Manager does not schedule a system notification. If the application is not running when the deadline passes, relaunching it restores the finished state without replaying the sound or completion alert.

While the completion alert is visible, only its alarm symbol performs short bursts of two or three
quick tilts and small lifts, separated by a brief pause. The card and text remain stationary. Each
presentation starts a fresh cycle; every dismissal stops the symbol's animation and restores its
resting transform. Hidden alerts never animate. With Reduce Motion enabled, the symbol is static,
including when the setting changes while the alert is visible. This does not change the alert's
five-second lifetime, click dismissal, sound or finished timer state.

The timer is separate from events and subtasks. It does not create an event, a subtask, an archive item, or any other durable task record.

## Events

An event contains:

- a title;
- an optional note;
- a calendar date;
- an optional additional emoji;
- zero to ten subtasks.

Multiple events may use the same date.

Event dates and countdowns use calendar-day semantics rather than elapsed-second calculations.

### Creating an event

A new event must use a date later than today.

Past dates and today cannot be selected as the date of a newly created event.

Saving the first event does not select a favorite automatically. The favorite choice in a new draft is initially off.

Ordinary event and day drafts start without an additional emoji. The editor offers `Без значка` to clear a selected emoji; Save accepts this empty choice. Editing an existing event preserves its stored emoji until the user changes or clears it.

Changes entered in the editor do not become event data until the user explicitly saves them.

### Creating a day

The header calendar control, labelled `Создать день`, reveals inline `Завтра` and `Выбрать дату` choices inside the event list. The existing `+` control still opens ordinary event creation directly. These choices do not open an action popover.

Both day choices open the existing editor as `Новый день`, initially dated tomorrow. `Выбрать дату` asks the user to choose a future date in the ordinary date field. A day draft starts without an additional emoji, with the Russian weekday name for its selected date, an empty note and no subtasks.

While the title has not been manually edited, changing the date updates the weekday title. After a manual title edit, later date changes preserve that custom title. All ordinary event fields remain editable.

Opening a day draft creates no persisted event. Save creates an ordinary event with the existing date, validation, primary-selection and expiry rules. Multiple events on the same date remain allowed. A repeated creation request while an editor is already open preserves that editor and its input rather than replacing it. Hiding and showing the panel also preserve the draft.

This is a single-day creation shortcut; it does not create a week or store reusable templates.

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

## Favorite and automatic event

Zero or one event may be explicitly selected as the favorite. It appears first and supplies the event representation in the menu bar when the timer is idle. Clicking its filled star clears the selection; clicking another event's unfilled star selects that event. The editor also permits clearing or setting the choice on Save.

With no favorite, the nearest active event starting with today supplies the menu bar and the large featured block. Equal dates retain stable user order. This automatic display never selects or persists a favorite.

Deleting or expiring a selected event clears the choice and returns to automatic display. Existing valid stored selections are preserved; an absent or invalid selection remains absent after normalization and restart.

## Event ordering

An explicitly selected favorite is displayed first. With no selection, all events use ascending calendar-date order starting with today.

All other events are ordered by ascending event date.

Events sharing the same date retain stable user order.

Their order must not change merely because titles or other content change.

## Subtasks

An event may contain between zero and ten subtasks.

A subtask contains:

- short text;
- a completed or incomplete state.

A subtask does not have:

- its own date;
- time;
- reminder;
- priority;
- nesting.

In the event editor, adding and removing subtask rows uses a 100-millisecond non-spring transition
of layout height and opacity. Existing rows move smoothly; typing text and its character count do
not animate. With Reduce Motion enabled, rows change immediately, including when the setting
changes during a transition. Stable subtask identifiers preserve other rows' text, completion state
and order. Rapid actions respect the ten-subtask limit and never focus a row that has been removed.
Adding retains the existing autofocus and scroll-to-row behavior. Removing a row remains a draft
change until Save, and removed row controls do not accept input or remain interactive accessibility
content.

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

Expanding and collapsing a checklist uses a short, non-spring transition of height and opacity lasting 200 milliseconds. With Reduce Motion enabled, it switches immediately. Rapid repeated clicks leave the checklist in the state requested by the last click; other events' disclosure states and event data remain unchanged. Collapsed subtasks do not receive input or remain exposed as interactive accessibility content.

## Menu bar

When the timer is idle, the menu bar represents the favorite, or the nearest active event starting with today when no favorite is selected.

Its normal event representation contains:

- the event emoji, or `📅` when no additional emoji is stored;
- remaining calendar days, or `Сегодня`.

It does not display:

- event title;
- event date;
- note;
- subtask text;
- subtask completion controls;
- subtask progress.

While the timer is running, its representation temporarily takes precedence and the menu bar displays the system alarm-clock symbol plus the remaining timer value. When the timer is finished but not yet deleted, the menu bar displays the alarm-clock symbol alone. Deleting the timer restores the normal primary-event representation.

When no events exist and the timer is idle, the menu bar displays:

`◷ Countdown`

## Empty state

When no events exist, the event area displays an empty state and provides an action to create a new event. The timer remains independently available.

## Editing and explicit actions

### Save

Save explicitly commits the current editor changes through the existing data-safety boundary. A successful Save ends the editing session and returns to the list. A failed Save keeps the editor and draft available and reports the error.

### Cancel

Cancel explicitly abandons the current unsaved editing action and returns to the list. It does not close the panel. Save and Cancel retain the list's browsing context; actual data changes may affect event order according to the ordering rules above.

### Delete

Deleting an event is an explicit destructive action and requires confirmation before removal. Cancelling confirmation preserves the editor and draft. Successful deletion ends editing of that event and returns to the list; a failed deletion retains the working context and reports the error.

Timer deletion is a separate lightweight action and does not require event-style confirmation.

### Session continuity

Closing, toggling or automatically hiding the panel does not commit or discard input, dismiss the editor or reset navigation. Reopening through the status item presents the same in-memory panel, hosting hierarchy, list position and editing session on the current Space. No transient editor-state persistence is required across application restarts. The separately defined durable checklist-collapse preference and timer deadline are unaffected.

If an event expires while its draft is open, expiry still applies to stored data. Keep the draft visible with an explanation that the event is no longer available; disable saving it as that event. Do not silently discard the input or recreate an expired event. Cancel remains available.

## Launch at login

Countdown Manager may be configured to launch automatically when the user signs in to macOS.

Launch at login is disabled by default.

The user may enable or disable it from the application interface.

## Persistence

Countdown Manager stores event data locally on the current Mac.

The production event data location is:

`~/Library/Application Support/CountdownManager/countdowns.json`

The single timer deadline is stored separately from event data in local application preferences. Timer ticking does not rewrite `countdowns.json` or perform per-second persistence writes.

Stored data must preserve existing supported event content across normal application restarts and compatible application updates.

Existing compatible data from older supported schema versions must remain readable unless an explicit future migration changes that contract.

Invalid or corrupted user data must fail safely.

The application must not silently overwrite invalid user data merely to recover from a read failure.

Newer successfully accepted event state must not be replaced later by an older delayed persistence operation.

The technical persistence design belongs in the relevant architecture decision.

## Privacy

Countdown Manager does not require cloud storage or an online account for normal product behaviour.

User event content and timer state remain local to the Mac.

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
- timer duration or completion outcome;
- success or failure;
- UI-stall detection.

Diagnostics are not a user-content log.

## Product non-goals

Countdown Manager currently does not provide:

- user accounts;
- cloud synchronization;
- multiple timers;
- named timers;
- timer pause or snooze;
- event or subtask notifications/reminders;
- event archives;
- overdue events;
- automatic event rollover;
- independent subtask dates;
- subtask priorities;
- nested subtasks.

These capabilities are product changes. They must not appear incidentally as part of an unrelated technical fix.
