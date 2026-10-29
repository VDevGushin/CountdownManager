# Countdown Manager — Product

## Purpose

Countdown Manager is a native macOS application for tracking today's and future events by calendar day, with a quick menu-bar panel and a larger desktop window.

The product is intentionally small and quiet. The central concept is an event date and the number of calendar days remaining until that date, including `Сегодня` on the event's date. The application also provides one lightweight countdown timer for short time-based reminders.

Countdown Manager is not a task manager or calendar replacement. Outside the single timer completion alert, it does not provide event or subtask reminder workflows.

The application does not require an account or internet connection for event and timer use.
Optional weather forecasts require a network connection.

## What's new

Release 1.19.0 includes a read-only `Что нового` screen explaining saved links, file/link
drag-and-drop and `Вставить текст как вложение…`. It is offered once on the first safe explicit
opening of the panel or desktop after installing this release, including a first installation.
Background/login startup and material-drag hover never trigger it. An active event/text editor,
native sheet, loading, material import, persistence, diagnostics export or updater UI defers it
until a later safe explicit opening; an active timer alone does not block it.

The release is marked presented only after its window becomes visible. Closing or pressing
`Понятно` acknowledges the presentation; restarting or reopening the app does not offer the same
release again. `Настройки → Что нового…` opens it again manually on either surface; the application
menu also provides `Что нового…` when the desktop activation policy exposes that menu. The read-only window
uses the existing appearance, leaves event/draft bytes and the timer untouched, and does not
change the application's activation policy. Opening from the mini-panel hides that panel;
an explicit close returns to the panel on the active Space when no desktop is visible and the
application is still active and admission is still safe. It does not reopen over updater/modal UI,
an editor or pending work, or after application deactivation.

## Primary interface

Accepted product contract for the menu-bar panel shell.

The menu-bar entry opens a temporary panel anchored directly below the status item. The application starts as a menu-bar utility without a Dock icon. Launch at login starts the menu-bar entry without opening either interface. The first explicit desktop opening makes the application available in the Dock for the rest of that application session. Closing its window, switching to the mini-panel or dismissing the panel changes visibility, not the application's role; Quit ends the session.

- Clicking the status item shows the panel from that status item on the current active macOS Space if hidden; clicking it while visible hides it. Every distinct click determines the next visible/hidden state even when clicks are rapid.
- The panel has no arrow, title bar or traffic-light controls. It is not draggable and never behaves as a centered or independently positioned utility window.
- Closing the panel, including through the standard close command, hides the interface without quitting the application.
- When the user leaves the panel, including switching to another application or Space, it automatically hides. Returning to the original Space does not show it again; only a new status-item click does.
- Hide/show preserves list browsing position, the current internal screen, an open editor and its unsaved input during the application session.
- Automatic hiding, the close command and the status-item toggle never mean Save, Cancel or Discard. Quit ends the editing session, while an active timer continues according to its persisted deadline.

The single timer is shown as a compact strip above the event interface. Event creation and editing, including subtask text and emoji selection, use the internal editor in the panel. There are no separate quick-subtask editors, action/context popovers or application-owned emoji popovers. The desktop window presents the same editor form in a sheet, with only one editing session allowed across both surfaces. Explicit controls replace these secondary flows. Primary-event selection and subtask completion remain directly available in the panel list.

The editor uses a compact 21-point Georgia heading and a scrolling form. Title, note and subtask text fields
use one native bezel and the native focus ring, without a second custom border. The native note field is
always visible, labelled `Заметка · необязательно`, with the `Пара слов о событии` placeholder and
a live character count starting at `0/150`, below the field at the right. The native multiline
field reserves three lines, grows to six, then scrolls vertically. Hiding and reopening the panel preserves the note text
along with the other draft fields. Title and date remain directly
available, and today's expiry warning retains its exact meaning in a quiet ochre treatment.

The additional emoji is an independent, outlined full-width field labelled `Значок`, displaying
`Без значка` or the selected emoji and a disclosure chevron. A separate small clear button appears
inside that field only when an emoji is selected; clearing must not also open the picker. The
weather, favorite and `Сохранять после даты события` native checkboxes form a distinct group below it, in that order, separated from the icon field by 13 points. Retention help stays directly below its checkbox.
Subtasks follow a separate section, with room prioritized for their editable text. The form scrolls
while Delete, Cancel and Save share one fixed bottom action row; deletion still requires an inline
confirmation. The field is a selection control, not an editable text input. The picker is initially
collapsed. Activating it reveals eight compact presets and a `Все значки` action; activating it
again collapses the picker. Opening or closing it preserves every draft field.

`Все значки` reveals the larger inline catalog organized into five named sets: `Общие`, `Дети`, `Работа`, `Транспорт` and `Праздники`. Each set is a six-row/eight-column page, fitting the editor's available inner width. The current set name is shown above conventional previous/next controls with page dots; horizontal drag/swipe may also change sets. The first set keeps the compact presets as its top row. Choosing any emoji or clearing the selection resets catalog navigation and collapses the entire picker. New selections come from the provided catalog; an existing stored valid emoji outside that catalog remains displayable and may be preserved until the user selects another one.

Picker disclosure uses a 200-millisecond non-spring height and opacity transition. The chevron communicates expansion, and changing the selected value may use a brief opacity transition. With Reduce Motion enabled, transitions are immediate. Rapid repeated requests finish in the state requested by the last action. Collapsed picker content does not receive input or remain exposed as interactive accessibility content.

Event deletion uses an explicit inline confirmation with a cancel action. Launch at login, diagnostics and Quit remain accessible through ordinary controls. A dedicated Restart action is removed; the application can be quit and launched normally.

Use ordinary controls inside the panel. The event interface uses a warm ivory palette with a terracotta accent and serif titles, with a related warm dark appearance and an Increase Contrast adaptation. Only an explicitly selected favorite receives the featured event treatment and larger calendar leaf on its right; other events have smaller calendar leaves on their left. Without a favorite, every event uses the ordinary compact card, including the nearest event and events dated today; every star is unfilled and no featured heading is shown. Each leaf shows the event's actual month and day, without a leading zero. A selected additional emoji appears immediately before the event title. Empty emoji and legacy `📅` are omitted from the list because the leaf already conveys the date; legacy stored values remain available in the editor.

Event cards express their civil-day distance as `Сегодня`, `Завтра`, then `Через N дней`
with correct Russian day forms. The exact date and event title remain visible and unchanged.
A featured card uses one 21-point Georgia line below the date: green for today and the
existing terracotta accent for future days. Retained past events use `Вчера` or `N дней назад` in neutral secondary ink, never a negative countdown or overdue warning. Secondary metadata is ordered `date · relative label`,
including today; only today's relative label is green. The menu bar uses `Сегодня`, `Завтра`, then its
compact numeric day format for future dates and `Вчера`/`N дней назад` for a retained past favorite. Labels are derived from the current civil day.

The featured title uses 23-point Georgia and a compact 54 × 65 calendar leaf; secondary events
use 14-point semibold titles and 42 × 51 leaves. The entire secondary header stays 51 points high,
including separate 28 × 28 favorite/edit actions. Actual title width, including emoji, determines
the layout: a one-line title has a separate date/count line and available weather line; a wrapping
title takes up to two lines with date/count/weather together below. Title line height is 17, metadata
font 11/line height 14, with 3-point gaps. Metadata does not wrap, and available weather follows the
countdown without an expanding spacer. No forecast placeholder is invented. The featured title/calendar/actions keep their existing metrics.

Every note uses 12-point text below the whole header, across the full 342-point content width.
The complete note wraps and preserves internal newlines, without a line limit, ellipsis, disclosure
or inner scrolling. Checklists follow the note. Featured weather sits immediately after the full date beneath the title,
with a middle dot and real forecast SF Symbol on the metadata baseline. This also applies to today.
Its separate countdown/green `Сегодня` line contains no duplicate forecast. Without an eligible
forecast or with showsWeather OFF, both forecast and its separator are absent. Each event and its checklist
form one visually separate block on a subtle surface, with space between events. Individual subtask rows have no horizontal separators. Completed subtasks remain readable and directly reopenable, with quieter text and neutral completion marks.

Opening the internal editor or settings must not reset the list underneath it. The inactive list must not receive input or remain exposed as interactive content to accessibility. Use simple native state-change animation for primary selection and subtask completion; avoid custom panel motion and forced focus transitions, and respect system accessibility and Reduce Motion settings.

New notes accept at most 150 Swift String graphemes, including emoji and newlines. A replacement
that would exceed the limit is rejected as a whole, preserving the accepted text; no prefix clipping
or partial-emoji truncation is allowed. Marked IME input is provisional, and committed edits, selection
and Undo retain native text behavior. The same limit is enforced at Save, not just in the editor.
Existing stored notes longer than 150 remain fully visible and load without truncation or migration.
For an active existing event only, the permitted length is max(150, its currently saved note length).
The note can stay that length or shrink while other fields, subtasks and primary selection remain
saveable. A successful shorter Save reduces this allowance; draft deletion/Undo does not. Deleted or
expired identities grant no allowance. Legacy counters show the real N/150 and a short explanation,
without treating permitted legacy content as invalid. The counter/input limit count raw graphemes;
Save retains existing outer-whitespace normalization for changed/new notes. An unchanged stored
note is preserved exactly. Internal newlines remain unchanged.

## Desktop window

The desktop window and mini-panel are two interfaces of one installed application, not separate
programs. They share the same events, explicit favorite, checklist completion, persistence, timer,
weather and settings owners. There is no second data file, synchronization service or account.
Opening a window does not migrate or copy event data.

`Открыть основное окно` opens or brings forward one retained, normally resizable macOS window.
Opening it hides the temporary panel without ending any panel editor. Dock reopening brings the
same desktop window forward. Unlike the mini-panel, the desktop window remains visible when
another application becomes active. Normal close hides the retained window, leaves its Dock entry
and keeps the menu-bar utility and timer running. Reopening preserves the selected view, search,
selection and in-memory browsing state. Quit still ends the entire application.

The desktop uses ordinary macOS Spaces behavior, respecting the user's Mission Control and
Dock assignment settings. Activating an existing window can switch to the Space containing it;
the app does not force that window onto the current Space or duplicate it across all Spaces.
The mini-panel remains a transient utility shown on the current Space. See the
[desktop activation decision](decisions/desktop-activation-and-spaces.md).

The desktop footer action `В мини-панель` explicitly switches to compact mode: it hides the
retained desktop window and opens the anchored panel without stopping the app or timer.
It is unavailable while a desktop editor or settings pane is open. Opening the panel from
the status-item icon does not hide the desktop window; toggling it again hides only the panel.
Returning through `Открыть основное окно` hides the panel and restores the retained window state.

The in-window command bar uses an icon-only native segmented control for collection (grid) and
feed (list), with a visible selected state, hover help and accessible names, search by event title
or note, and event creation. There is no separate favorite-only filter: only one event can be
favorite, and both views already show the same featured favorite card above ordinary events;
the nearest event never substitutes for an absent favorite. Ordinary events follow stable date
order, preserving existing order for equal dates, grouped under month-and-year headings in both
views. Retained past ordinary events follow all future sections in one final `Прошедшие` section,
most recent first and stable for equal dates. A retained past favorite remains above all groups and
is not duplicated in `Прошедшие`. The mini-panel uses the same favorite/future/past order without month or past section headings. Empty months are omitted; a favorite is not duplicated inside its month. Switching views
reflows the same event identities in a short, approximately 0.15-second non-spring animation;
the calendar, title and metadata retain their visual identities instead of instantly replacing
one card composition with another. Month headings and cards move in the same layout transaction.
Text is not scaled and the whole list is not faded out. Reduce Motion changes layouts immediately.
Rapid switching follows the latest selection without changing saved data or the divider.
The featured favorite places its date and eligible forecast together on a full-width metadata
row below the title/calendar identity, so the narrow browser pane retains room for both.
Empty search/filter results offer a return to
all events, rather than implying that saved events were deleted. Selection follows a surviving
visible identity; if it disappears through filtering, deletion or expiry, the next visible event
is selected, or the details become empty if none remain. Loading and unavailable/recovering data
remain distinct from a genuinely empty saved collection; a read failure must not claim that no
events exist.

The left side selects events and summarizes their date, remaining time and preparation progress.
Desktop collection cards, feed rows and the featured favorite show a separate paperclip with the
number of saved attachments when that number is positive. It is independent of the optional
event emoji and checklist progress. With no attachments, no paperclip, zero count or placeholder
is shown. The indicator is a summary, not another file-editing action.
In the collection grid, relative labels (`Сегодня`, `Завтра`, `Через N дней`) sit at the bottom
of ordinary cards with a consistent inset and align across each row, regardless of title wrapping
or forecast presence. Exact dates and forecasts remain above them.
Checklist checkboxes, favorite changes and editing belong to the right-hand event details,
consistently in both collection and feed. A complete nonempty checklist has a green completion
indicator; reopening a task restores the incomplete presentation. Completing or reopening a task
repositions the same row identities in a local 150 ms ease-in-out animation. Reduce Motion makes
that reordering immediate; persistence, accepted action order and neighboring controls are unchanged.
A zero-task event has no fake
`0/0` completion state. The event's additional emoji appears in the secondary date line in
collection, feed, favorite cards and details, rather than prefixed to its desktop title or attached
to its calendar leaf. Without an emoji, this line has no reserved icon space. The mini-panel's
existing emoji placement is unchanged. Notes and preparation remain readable in independently scrolling
details. Weather appears only when the shared setting and applicable per-event choice allow a
real eligible forecast; missing data does not produce invented temperatures or placeholders.
Under `Впереди`, the desktop overview shows the current date and an eligible forecast for today
on one line. An absent or disabled forecast adds no visible or accessible placeholder; the date
position, metadata-line height and content below remain stable as the forecast appears or disappears.
Ordinary desktop feed rows align the calendar at the top with the event title and place
the relative remaining-time label at the upper right. The exact date and eligible weather
share one line, with temperature after the date; checklist progress and attachment count
share a separate horizontal summary line. Their compact height does not reserve a separate
weather row or stack the two counts. Collection grid cards retain their reserved weather row.
The desktop details use a compact title/calendar identity followed by one full-width date and
eligible-temperature line, then the remaining-time label. Date and weather are separated only
by spacing, without a middle dot, consistently with desktop feed and favorite cards.
A saved empty note adds no section;
the note field remains available in the editor. Nonempty notes and long titles remain fully
readable in the scrolling details. Arriving, disappearing or
disabled forecasts must not shift surrounding content for otherwise unchanged events and
window geometry.
This layout rule and checklist animation apply only to the desktop, not the mini-panel.

The desktop details header has three equal icon-only controls: favorite, a simple pencil for
direct editing, and trash for direct event deletion. There is no persistent editing caption or
overflow menu; accessible names and hover help identify the actions. An unselected outline star
uses the same neutral primary ink as pencil and trash. Only the selected filled star uses accent
color. This state-based color rule is desktop-only. Trash opens an
inline confirmation naming the target event and warning that deletion cannot be undone. Only
explicit confirmation deletes it; Cancel or selecting another event does not change saved data.
Successful deletion follows the existing visible-selection rules, including an empty collection
after the final event. The shared editor and persistence guards also apply to this route; a failed
save reports the error and retains the event. Mini-panel deletion still uses its existing editor.

The desktop has no timer strip or timer controls. The single timer remains available in the
mini-panel and menu bar; opening, closing or changing the desktop layout never resets its deadline,
completion alert or update-restart protection. The mini-panel retains its existing timer layout.

Desktop checklist and favorite actions are processed in acceptance order without briefly disabling
unrelated controls for each local save. An editor requested during these writes opens only after
earlier accepted actions finish, using the latest event. Existing loading, recovery and cross-surface
editor restrictions still apply. A failed action reports the failure and any unperformed queued
actions explicitly rather than silently losing accepted input. This does not change mini-panel
interaction rules or the shared persistence format.

A native draggable divider resizes the browser and details. Each side retains at least one third
of usable split width and a 320-point content floor; the desktop window has a 960 × 640-point
minimum content size. Long notes, lists and titles must not force either pane offscreen.
The visible divider stays thin, while a 12-point-wide pointer target centered on it supports
dragging from either side and shows the horizontal resize cursor. Outside that band, ordinary
content interaction is unchanged.
The user-adjusted divider position survives ordinary event actions, selection, collection/feed
switching, searches and editor/settings transitions during the window session. Resizing may clamp
the panes to their legal minimums, but ordinary content changes must not reset the split.

The existing editor form is reused in a desktop sheet. Save and Cancel are the explicit ways to
finish or abandon its draft. Closing the desktop window or using Command-W while its editor is
active does not dismiss that draft; finish with Save or Cancel first. The panel and desktop cannot
open editors simultaneously, and event mutations on the other surface are unavailable until the
editor finishes. The other interface can still show current data and return to the active editor.
Both editor owners block update installation/restart. Desktop settings reuse the existing settings
form in a native 430 × 560-point sheet attached to the desktop window, bound to the same preferences.
Its header shows `Настройки` on the left and a close button on the right, and it dims the event interface.
The close button, Escape or clicking the dimmed area
closes settings; the outside click is consumed rather than selecting or activating an event behind
the pane. Clicking inside settings does not close it. The event interface stays mounted but is
disabled, excluded from hit testing and hidden from accessibility while settings is open. Dismissal
preserves the selected event, view, search and divider position. Settings has no independent window.
The diagnostic Save dialog attaches to the settings sheet, which remains open until export finishes.
Settings entry does not replace an active editor. The editor's outside-click protection is unchanged.
Desktop Settings, file libraries and create/edit use the same native sheet presentation and
system opening/closing animation. macOS owns timing and Reduce Motion behavior. The background
remains inactive until native dismissal completes. Settings and file-library close buttons,
Escape and clicks on the parent content outside the sheet share their dismissal path; the
editor requires Save or Cancel. Losing a file library's owning event requests native dismissal.

Command-N creates an event in the desktop window. The footer Settings button and Command-comma
open the centered settings pane when no editor is active. Ordinary
native controls retain keyboard focus and accessibility labels. Collection/feed selection and
search are window-local browsing choices, not changes to saved event data.

## Settings

Desktop settings and editor surfaces use the same explicit canvas, primary/secondary ink and accent
palette in Light/Dark/System appearance. Native field bezels and focus rings remain system controls;
they are not replaced with custom outlines. The desktop settings pane follows the same appearance
owner as the main window and mini-panel, without an application-wide override of status-item colors.
These desktop presentation changes do not alter the mini-panel settings or editor palette.

In the mini-panel, Settings is an internal screen in the same retained 390 × 600 panel. The 60-point timer strip
remains above the 540-point manager area on both the list and settings screens; timer actions
remain available. Settings navigation does not open another window, sheet or popover. The explicit diagnostic
export action uses the native macOS save dialog.

The panel list footer remains a single compact row: `Хранится на этом Mac`, an `Открыть основное окно`
button, a small settings gear immediately before `Выйти`, and `Выйти`. The gear has a 14-point
visible symbol and a 22-point activation area. The header retains its existing calendar and `+`
creation controls.

Settings arranges existing controls into three groups:

1. `Приложение`: launch at login, automatic update checks, and `Не давать Mac и экрану засыпать`,
   with the existing saved-intent explanation and recovery actions;
2. `Погода`: `Показывать погоду в днях` and the existing location choice;
3. `Обслуживание`: `Проверить обновления…`, replaced by `Обновление готово · установить…`
   while installation is deferred, and `Сохранить диагностику…`.

The weather section adds `Показывать погоду в днях` and a location choice. The location choice is
unavailable while weather is off. Provider, licence, privacy, loading and error explanations are
absent from the weather UI. A small secondary `Версия <version>` at the bottom reads the running
bundle's short version; no hardcoded version or build details are shown.

The action buttons perform their named actions and do not use navigation arrows. An unconfigured
updater leaves update controls unavailable; settings does not start a placeholder feed. A login
item that requires macOS approval retains the explicit `Разрешить в настройках macOS…` affordance.
Failures remain visible and must not report an operation as successful.

Settings choices persist across launches and app updates in their existing owners: login registration
in macOS, automatic update checks in Sparkle, and weather/keep-awake preferences in the unchanged
`local.countdownmanager.app` defaults domain. Updating the bundle does not reset preferences or
event data. No defaults migration or production-data reset is introduced.

The shared `Тема` setting offers `Системная`, `Светлая` and `Тёмная`. System is the default and
follows macOS; an explicit choice applies immediately to both desktop and mini-panel, including
their settings/editor surfaces, and persists across launches in the same preferences domain.
Changing application theme does not change macOS appearance or the system menu-bar background.

Settings changes apply immediately without Save/Cancel. In the mini-panel, `Назад` returns to the same list and its
browsing position. Hiding and showing the panel retains the current settings screen. Entry is
available only from the list; it cannot replace an open editor or discard its draft. Settings is
not an event editor and does not itself block an update restart. Existing timer, editor and
persistence restart guards still apply to the ready-update action.

### Keep awake

`Не спать` prevents automatic idle sleep of the computer and display while Countdown Manager is
running and the mode is enabled. The checkbox and accent indicate the active mode in settings;
a small state dot on the gear indicates it on the list without adding another footer row.

The choice persists across launches and updates. Without a saved choice it starts off; a saved ON
requests sleep prevention during startup, including after an update restart or launch at login.
Termination releases the process assertion without clearing the saved choice. Explicit OFF releases
it and saves OFF. Opening settings, going Back, hiding the panel, changing Spaces, and starting,
completing or deleting a timer do not turn it off; the feature remains independent of the timer.

The control changes its displayed state only after macOS accepts the requested change. A failed
enable leaves it off; a failed disable leaves the existing active state visible and reports an
error so the user can retry. If startup restoration fails, the checkbox shows inactive with an error,
but the saved ON is retained for the next launch. The user can retry the checkbox, or use the
conditional `Не включать при запуске` action to clear that saved intent while the mode is inactive.
The mode does not promise to prevent a screen saver, security lock,
lid-close sleep, manual sleep, low-battery sleep or other system sleep reasons. It does not wake
an already sleeping display or change the Mac's global power or security settings.

## Timer

Countdown Manager exposes exactly one timer.

The timer has no user-editable name or task text. Its visual identity is simply `⏰`.

When idle, the selected duration uses a quiet tinted selection surface; the filled Play action
remains the stronger accent. The user chooses one of seven fixed durations: `5`, `10`, `15`, `30`, `40`, `60`, or `120` minutes, then starts the timer. There is no custom-duration input.

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
- a persisted automatic-title choice;
- an optional note;
- a calendar date;
- an optional additional emoji;
- zero to ten subtasks;
- optional local file attachments;
- an optional weather-display choice;
- an optional retain-after-date choice, off by default and independent of the favorite.

Multiple events may use the same date.

Event dates and countdowns use calendar-day semantics rather than elapsed-second calculations.

### Creating an event

A new event may use today's date or a future date. The ordinary header `+` initially selects
tomorrow; empty-state creation offers today, tomorrow or the native date-selection route.

New events cannot use past dates, including when retention is selected. Date validation uses the current calendar day when saving, including when a draft remains open across midnight.

Saving the first event does not select a favorite automatically. The favorite choice in a new draft is initially off.

Ordinary event and day drafts start without an additional emoji. The editor offers `Без значка` to clear a selected emoji; Save accepts this empty choice. Editing an existing event preserves its stored emoji until the user changes or clears it.

Changes entered in the editor do not become event data until the user explicitly saves them.

### Creating a day

The header calendar control, labelled `Создать день`, reveals inline `Сегодня`, `Завтра` and `Выбрать дату` choices inside the event list. The existing `+` control still opens ordinary event creation directly. These choices do not open an action popover.

All day choices open the existing editor as `Новый день`. `Сегодня` initially selects today; `Завтра` and `Выбрать дату` initially select tomorrow. `Выбрать дату` asks the user to choose today's date or a future date in the ordinary date field. A day draft starts without an additional emoji, with the Russian weekday name for its selected date, an empty note and no subtasks. Its `Показывать погоду для этого дня` checkbox is initially on; ordinary `+` drafts start with it off.

Day drafts start with automatic titles enabled. Changing the selected event date updates the Russian
weekday title until a real manual text change switches the draft to a custom title. All ordinary
event fields remain editable. The title mode is saved with the event and restored when editing it.

Opening a day draft creates no persisted event. Save creates an ordinary event with the existing date, validation, primary-selection and expiry rules. Multiple events on the same date remain allowed. A repeated creation request while an editor is already open preserves that editor and its input rather than replacing it. Hiding and showing the panel also preserve the draft.

This is a single-day creation shortcut; it does not create a week or store reusable templates.

### Editing an event

An existing event remains editable while available, including after its date when retention was saved.

An available event may be moved to today's date or a future date. A retained past event may keep
its original saved date while editing its title, note, subtasks, attachments and other options; it
cannot move to another past date. Turning retention off for a past event and pressing Save opens
an explicit deletion confirmation. Cancel keeps the event and draft available; confirmed deletion
uses the ordinary durable deletion boundary and removes owned copies only after persistence succeeds.
A failed deletion keeps the draft and existing event/files available for retry.

Editing does not change durable event data until the user explicitly saves.

### Automatic event titles

An event's title is either automatic or custom. Automatic means the Russian weekday of its selected
event date, including after Save, reopening or application restart. Changing the date of an automatic
event updates the draft title immediately; successful Save commits date, title and mode together.
The mutation boundary derives the canonical automatic title from the saved date.

Ordinary `+` drafts start with a custom empty title; day-creation drafts start automatic. Existing
events restore their saved mode. Events whose JSON lacks the mode remain custom, even when their
title equals a weekday name. No title-based migration or guessing is allowed.

A real user text change immediately switches the current draft to custom mode. Merely focusing or
selecting text, accepting the same value again, or the application's date-driven update does not.
Undo may restore text, but does not enable automatic mode. While custom, changing dates preserves
the user's title. Blank or whitespace-only custom titles cannot be saved.

The editor provides `Название по дате` next to the title for custom drafts, including ordinary and
legacy events. It immediately replaces the draft title with the selected date's weekday and enables
automatic mode. It changes no note, emoji, subtask, favorite or weather choice. The new mode and
replacement text become durable only after successful Save. Cancel restores the saved title/date/mode;
write failure leaves durable data intact and keeps the entire draft available for an explicit retry.
Hiding and reopening the panel retains the unsaved draft and its mode. Removed or expired identities
remain unavailable and cannot be recreated by switching title mode.

Automatic naming does not move an event's date, roll events forward at midnight or alter expiry.
The event date remains the source of the weekday name; clocks, restarts and panel visibility do not
reschedule it.

`Показывать погоду для этого дня` is available in the editor for new and existing events. Save
persists this choice; Cancel keeps the previously saved value. Changing a title or date does not
infer or reset the choice. Existing events, including weekday-titled events, remain opted out
unless the user explicitly changes them. No title-based migration or separate persisted day type
is introduced.

### Today

An event remains active and available throughout its entire calendar date.

On that date, its countdown is represented as `Сегодня`.

The event remains editable and removable during that day.

When an editor's selected date is today and retention is off, it shows `После окончания дня событие будет удалено, включая незавершённые подзадачи и прикреплённые копии файлов. Исходные файлы сохранятся.` This applies to ordinary event creation, day creation and editing an existing event.

### Expiry

After an event's calendar date has ended, it expires automatically unless `Сохранять после даты события`
was saved. Expired events are removed rather than moved into an archive. Incomplete subtasks do not
prevent expiry.

A retained event keeps its identity, exact date, note, subtasks and attachment copies until explicit
deletion. The editor explains `Событие и вложения останутся, пока вы их не удалите.` Retention is off
for ordinary/day creation and legacy events, and is committed only by Save. An unsaved retention
change cannot prevent stored expiry across midnight. A saved retained event remains editable across
midnight even if its open draft has retention switched off.

Retained past events are past dates, not overdue tasks. There is no automatic rollover, separate
archive screen or implicit retention based on favorite status or attachments.

### Adding materials by drag and paste

A saved event accepts ordinary local files and HTTP/HTTPS links on its desktop browser card,
desktop details or mini-panel card. The target is the receiving event, including an unselected
card; dropping does not change another event. Hover adds a stationary accent outline/tint without
changing the card geometry or disclosure state. One preferred representation is used per dropped
item: a file URL has priority over a web URL, followed by plain text. Unsupported schemes, folders,
packages and symbolic links are rejected. File promises from Mail/Photos are not advertised.

A successful saved-event addition commits immediately. There is no addition-Undo action,
receipt or status/progress/success row on either surface, and no replacement toast or notification.
The event's existing file/link counts show the saved result. Existing editor Save/Cancel and native
text Undo/Redo retain their normal meaning. A potential future undo of deletion is a separate
feature and is not implemented by this intake flow. Removal/expiry cannot resurrect an event.
Both existing limits apply before importing a batch. A failed saved-event batch commits
none of its materials and cleans up temporary owned copies. Failed writes preserve durable data.
The pending addition blocks another addition and entry to an editor until it finishes.

The event context menu exposes `Вставить текст как вложение…`. In desktop details, Paste also
opens it when an event is selected and no text field is editing; text-field Paste keeps its normal
meaning. Clipboard text is read only in response to an explicit paste/menu/button action. A plain
text drop opens the same composer. It previews the complete editable text and proposes a filename
from its first nonempty line. The user may change both. `Создать вложение` writes a UTF-8 `.txt`
without trimming or truncating its content; paragraphs and trailing newlines survive. Rich text
formatting is not preserved. This uses one of the 15 attachment slots and the existing preview,
expiry and owned-file cleanup rules. Empty text and unsafe/overlong names cannot be submitted.

The shared editor accepts drops into its retained draft and offers the text action beside its
attachment controls. Nested text composition retains the surrounding editor and attachment session.
Cancelling the composer returns to that draft. Whole-event Save/Cancel retains its existing meaning;
cancelling the event discards draft-only text files as well as imported copies. Mini hide/show retains
the composer, as for the existing editor. Desktop composition uses the existing native sheet owner;
mini composition uses the internal manager screen under the same timer.

Rapid hide/show requests must preserve the latest explicit show. A still-pending show is not
cancelled by an unconfirmed hidden occlusion observation; subsequent confirmed full occlusion and
explicit deactivation/Space/close retain their existing hide behavior.

Hovering a supported drag over the status icon reveals the anchored mini-panel without activating
the app or committing anything. The user then drops onto a specific event; the icon itself does not
accept a drop. Ordinary status-item clicks and panel hide/Space rules retain their existing meaning.

### Links

An event may contain up to ten web links. Each has stable identity, an optional name and a required
full HTTP/HTTPS address. Outer whitespace is removed on Save. Other schemes, missing hosts,
embedded whitespace and URL credentials are rejected. A missing name displays the domain.
No network request, preview, favicon or page download occurs merely by saving or rendering a link.

The shared event editor adds, changes and removes link rows after attachments. Each row contains
name and address fields and the same native trash symbol used for subtasks. Invalid or incomplete
rows block Save and show an inline address explanation after leaving a field. Removing the row
allows Save again. The count is N/10; Add is disabled at ten and explains how to make room.
All link edits remain in the event draft until Save; Cancel preserves saved links. Failed writes
retain the draft for retry. New event and day drafts start without links.

Saved desktop details and mini-panel cards show a compact Links section after attachments only
when nonempty. Desktop section headings pair «Ссылки» at the left with a trailing neutral
saved-link count and link symbol, matching the attachments count/paperclip and checklist
progress/symbol. All three right-hand summaries use value then symbol in one trailing column. Each row shows name/domain plus link and external-opening symbols. The entire row
is keyboard-accessible and opens the current saved address in the default browser. Full address
is available as hover help. The action validates the owning active event and saved link identity;
stale, removed or expired links cannot open. Failed opening reports an error without deleting data.
Desktop collection cards, feed rows and the featured favorite show a neutral link symbol and
saved-link count alongside checklist/file summaries when positive. Browser summary labels
place the number/progress first and the symbol after it. Grid summaries align the three symbols
in one trailing column; favorite/feed summaries use the same value-then-symbol order.
 Zero links produce no symbol,
count or accessible placeholder. This is a summary, not a new opening/editing action; file-preview
behavior is unchanged.
In the mini-panel, the section starts collapsed like attachments: a fixed chevron, semibold heading
and trailing count form one full-width disclosure button. Opening or closing it changes no saved
event data; hidden rows are absent from input and accessibility. Hide/show retains its current
state during the mounted panel session; a fresh app launch starts collapsed. Desktop links stay
expanded and do not gain a disclosure control. At zero links the saved section remains absent.


Old JSON without links reads as an empty list; empty lists are omitted on write. Invalid present
metadata is not silently discarded. Older application versions do not preserve unknown link data
when writing: backward reading does not imply downgrade safety. Links expire with their event.

### Attachments

An event may contain local file attachments: photos, videos, documents and exported correspondence
are ordinary files. Adding an attachment imports an independent local copy; it does not link to
or modify the original. Copies survive application restarts and are shared by the desktop and
mini-panel as part of the same event. There is no upload, cloud storage or messenger integration.
Folders, application packages and symbolic links are not file attachments.

The relative content order in desktop details, mini-panel cards and the shared editor is note,
`Подзадачи`, then `Вложения`. Subtask and attachment section headings use the same readable
semibold weight and primary ink; desktop no longer calls its checklist `Подготовиться`.
Empty saved attachment sections are absent. The editor retains its attachment controls at zero
so files can still be added.

The shared event editor adds and removes attachments in its draft. New attachment collections
have a maximum of 15 files per event. The editor shows `N/15`, disables Add when its current
draft contains 15 or more files, and explains the limit visibly. Removing a draft entry from
15 to 14 immediately permits one new file before Save. If a native picker selection exceeds
the remaining capacity, reject the entire selected batch before copying any of it; explain
how many slots remain and preserve the prior draft. This count rejection is distinct from an
I/O failure during an otherwise admissible import, which preserves already completed copies.
Legacy events with more than 15 stored files remain readable without truncation or a load error.
They can keep their existing files, save unrelated fields and remove files. New files are
unavailable until the current draft is below 15; no automatic pruning or migration applies.
Save commits the draft; Cancel preserves previously saved attachments and discards newly imported copies. Hiding the
mini-panel retains the draft. Import or Save failure reports the problem and preserves completed
imports for retry or explicit cancellation. While file selection or copying is active, duplicate
requests and Save cannot race with that work. Cancel closes the editor without waiting for an
in-progress file copy; cancellation/token checks reject its late result and asynchronous cleanup
removes the abandoned copy after the filesystem operation settles.

Desktop details show a two-column shelf of the first four saved files after subtasks, with
their names and import-time sizes. The expanded mini-panel section shows the first three files
in one row of three columns. A single file occupies the first column without stretching.
Desktop preview canvases have a fixed 88-point height; mini canvases have a fixed 68-point height.
Every file format is offered for best-effort native preview: photo thumbnails, the complete
first PDF page, a static movie frame or another macOS preview. Loading or failing a preview
retains its area, filename and file-type fallback. Each whole tile is one explicit preview action.
`Показать все N` appears above four desktop files or above three mini files and opens the complete
saved collection. Expanding or collapsing the compact attachment
section keeps its heading and count at the same horizontal positions, as the subtask disclosure does.
All opens a separate bounded, read-only searchable list. Desktop uses the shared native
sheet with the title `Вложение` on the left and a close button on the right, without a Back
button or count in that header. The cross, `Escape`, or a click on the surrounding dimmed
background closes it, as in desktop Settings. The dismissing click cannot activate an event
or another control underneath; clicks inside the list do not dismiss it. The mini-panel keeps
its internal screen with `Вложения` and the same plain left-chevron `Назад` control as
mini-panel Settings, without a duplicate count in the header,
preserving the retained panel rather than adding a popover. Both surfaces show `Файлов: N` in
the footer while the trimmed search is empty and `Найдено: X из N` for a nonempty search.
Search filters by filename only, with a clear action and a useful no-results state; it does
not change saved order, counts, tasks or data. The complete list scrolls inside that surface,
using 44-point desktop and 36-point mini previews. Closing/Back restores the same event and
browsing context. Search state belongs to that presentation and resets for a different event.
If the owning event is deleted or expires, its file library closes and normal visible-selection
rules apply. Inactive parent content cannot receive input or remain interactive in accessibility.
The shared editor uses the same static preview/fallback presentation in fixed 36 × 36-point
areas, both for imported files before Save and for saved files after reopening. It retains the
full editable attachment list; preview availability does not affect Save, Cancel or file removal.
The event pencil is the sole entry to the shared editor on both surfaces. Saved desktop
note, subtask and attachment sections have no secondary editor-entry buttons, including
empty-note and empty-subtask states. Direct subtask checkboxes, file opening and
`Показать все N` remain available without entering the editor. The compact attachment section
also exposes no duplicate add/change button.
Opening a saved attachment first shows a large, read-only native quick preview in the originating
surface. Desktop reuses the single native sheet; the mini-panel uses an internal screen with
its usual plain Back chevron. The preview shows the filename and one derived `i из N` position.
Previous/next buttons and the unmodified Left/Right arrow keys traverse the entire event's saved
order in both surfaces, including when opened from filtered search;
they stop at the ends without wrapping. Legacy collections above 15 remain fully navigable.
An explicit `Открыть в приложении` action launches the active local copy in its default application;
previewing never autoplays video. macOS provides best-effort content or its native fallback for
existing unsupported/corrupt files. A missing copy shows a readable unavailable state, retains its
name and navigation, and disables external opening.
Closing the top preview through Back/cross/Escape or the desktop backdrop returns to its source:
the same event or the same mounted library with its query and scrolling context. The dismissal
click cannot activate the background. The underlying source is inactive for input/accessibility
while the preview is visible. Removing the selected attachment closes its preview to the valid
source; removing the last file also closes the library. Deleting or expiring the owning event
closes all its file presentations. Late asynchronous work cannot revive a closed preview or show
an earlier file under a new filename. Preview browsing never changes JSON, saved order, task state
or attachment copies, and creates no application-owned preview archive.
Missing copies remain identifiable and removable in the editor rather than disappearing silently
or blocking unrelated event edits.

Attachments follow the existing event lifetime. Deleting an event, removing an attachment with
Save, or automatic event expiry removes the corresponding application-owned copies after the
event change reaches disk. Retained events keep their copies after the date, including through
restart, preview and unrelated edits. The original files remain untouched. There is no attachment archive
and no automatic extension of an event's date. Only the editor and event-deletion confirmation
explain expiry/removal of copies; ordinary saved summaries and All-files lists do not repeat
that explanation. Cleanup failure is reported separately from successful event
saving and can be retried without rolling back an already committed event change.

Legacy JSON without attachments can be read by the new version; this does not establish safe
downgrading. Version 1.15.0 ignores the unknown attachment metadata and drops it when it writes
events. Restoring attachment associations requires a matched backup of the JSON and `Attachments/`
directory. Merely retaining the files or reinstalling the new version is not a restoration guarantee.

## Weather in days

Weather is globally off on first launch. Enablement and Automatic/manual city persist independently
of each event's saved `showsWeather` choice. New day drafts default true; ordinary and legacy events
remain false. Save commits that choice and Cancel leaves it unchanged; titles never classify events.

An eligible event shows only a native condition symbol and signed rounded Celsius temperature beside
its date/countdown area when usable forecast data exists. The element is plain text/symbol, without a link, tooltip,
source/license/privacy text, info button, loading/error/retry or placeholder. Weather settings contain
only the global switch and the Automatic/ten-city choice. Privacy-limited technical weather
diagnostics use the existing local journal and do not add weather status or errors to the UI.
The existing storage footer, event ordering, favorites, expiry and timer behavior stay unchanged.

Three keyless services are queried independently: [Open-Meteo](https://open-meteo.com/en/docs),
[MET Norway](https://api.met.no/weatherapi/locationforecast/2.0/documentation), and
[wttr.is](https://github.com/chubin/wttr.in). Their horizons differ (up to sixteen days, roughly nine,
and three respectively); a service failure cannot block useful results from another. Distinct services
may share weather models, so the combination is a heuristic, not a claim of independent evidence or
improved accuracy. No registration, weather key, credential form or secret is required.

Numeric fields use matching local Gregorian days and actual covered periods. Full days and remaining
hours are never averaged together. The temperature is the median of available full-day maxima (one
value directly, two averaged, three median), then rounded. MET prefers valid interval maxima; a full,
valid hourly forecast may instead contribute its sampled-hourly maximum without guessing peaks
between hours. A badge requires a full-day temperature and category; partial-day results stay internal.
Liquid rainfall is the raw median of comparable complete totals in mm, remains optional and is not
shown. Missing/invalid amounts are not zero; snow depth and mixed/frozen precipitation are not liquid
rain. Categories get one vote per service; the majority wins, with a wet category preferred on ties.

Manual cities use their known IANA zones. Automatic currently uses the Mac's configured time zone
for all services; that is not proof of the coordinate area's time zone if the Mac zone is set incorrectly.
DST intervals have their actual 23/24/25-hour length. A source's fixed 24-hour aggregates are not clipped
to pretend to cover different local hours. Missing or incompatible values yield no badge.

One batch per source/location/date range serves every eligible event. Responses publish progressively.
A fresh source cache remains usable during other requests; expired data disappears autonomously.
Freshness follows HTTP max-age (ahead of Expires), Date, Age and request duration. Missing freshness
has an explicit conservative 1800-second heuristic budget; malformed/conflicting relevant headers
do not silently receive a new budget. Data disappears at expiry. no-cache requires revalidation;
no-store does not retain a body. Neither feeds a long-lived badge. must-revalidate never permits
stale display. 304 applies only to an exact cached representation with a matching validator; missing
fields preserve prior restrictions. A header-free or lifetime-free 304 cannot restart a heuristic
1800 seconds. Orphan/mismatched304 schedules a bounded unconditional GET, without borrowing a body
from another area/range.

Temporary connection errors, 408 and retryable 5xx may use two rapid retries (10–20 then 45–75 seconds)
only while required dates remain uncovered within that source's horizon. A successful partial day
does not trigger rapid polling for missing hours. Expensive/constrained paths and Low Power disable
rapid retries. Otherwise failures use 300–360,900–1080, then 1800–2160 seconds. Permanent schema/units,
ordinary 4xx and TLS errors use 1800–2160 seconds. Cancellation adds neither a failure nor an automatic
retry. A zero-freshness 200/304 gets one 60–90-second recheck, then normal backoff; a short positive
TTL rechecks at expiry plus 0–15 seconds, at least 60 seconds after receipt. Long TTL is honored.

429/503 have no rapid series and a provider-wide minimum 300–360 seconds plus Retry-After.
Server cooldown and a sliding budget of six admitted starts per source per ten minutes survive
city changes and OFF/ON within the process. Rapid allowances are not replenished by refresh, event
reordering or panel reopening. Usable success resets them; after at least 30 minutes without starts,
a quiescent source can begin a new series. An active failing chain keeps its upper backoff stage.

Intervals after receipt use ContinuousClock, including sleep. A wall/monotonic discrepancy over 60
seconds withdraws doubtful freshness and schedules a bounded check; server gates/backoff do not move
earlier with wall-clock rollback. Wake/clock/calendar refresh coalesces overdue work without catch-up.
One NWPathMonitor runs only while ON with eligible demand. Unknown permits the first request;
known offline suppresses GET while freshness still expires. Recovery is debounced 2–5 seconds and
cannot bypass server/budget gates. After at least 60 seconds offline, one ordinary connection backoff
may be relaxed without resetting rapid allowances. A satisfied path does not prove VPN/host access.

OFF, location changes, empty demand and shutdown cancel work; old outcomes cannot restore badges.
An observed late Retry-After may still extend the provider-wide gate, without publishing old data.
Memory stays bounded to four area/range contexts of three sources/sixteen days and three small
provider-policy records. There is no disk cache, persisted AUTO location or stale badge mode.

Network requests, decoding and consensus normalization do not occupy the UI actor. Deleting an
eligible event immediately removes its weather demand. Shared work continues while other eligible
events still need it; deleting the last one cancels requests, location and scheduled refreshes.
Superseded computations cannot publish after demand or source results change. Cancellation is
cooperative: Foundation JSON decoding is checked immediately before/after, not interrupted mid-call.

Automatic uses native CoreLocation, never IP geolocation. Coordinates are coarse and rounded to two
decimals before HTTPS requests; manual cities need no device-location permission. An undetermined
permission is allowed only by explicit enable/AUTO or a successful foreground Save of an eligible
weather-enabled event. Restore, Cancel and failed saves cannot prompt. No eligible demand or weather
OFF means no forecast/location request. Isolated app runtimes keep synthetic providers and disable
native location and weather HTTP; authorized public-city probes are separate evidence.

The fixed manual list is Москва, Санкт-Петербург, Казань, Грозный, Нижний Новгород, Екатеринбург,
Новосибирск, Самара, Ростов-на-Дону and Краснодар. Weather choices do not mutate event content.

## Current date in the list header

For a nonempty list, the app name is removed from the list header. A compact Russian date, such as `Пт, 16 октября`,
comes first in system 15-point semibold type, without a year. A secondary 11-point event count
follows with a 3-point gap: `1 событие`, `2 события`, `6 событий`, with the corresponding Russian
endings for other counts. The existing 31 × 31 calendar and add buttons remain beside these lines.
The header uses horizontal 16-point and vertical 12-point padding. The date reads `Store.today`
and updates through existing midnight, wake, clock/calendar changes and reopening refresh boundaries.
No timer or duplicate date owner is added to the view. Both lines remain visible at panel width 390.

## Favorite and automatic event

Zero or one event may be explicitly selected as the favorite. It appears first and supplies the event representation in the menu bar when the timer is idle. Clicking its filled star clears the selection; clicking another event's unfilled star selects that event. The editor also permits clearing or setting the choice on Save.

With no favorite, all active events use ordinary compact cards in ascending date order, starting with today. The idle menu bar shows the Mars application symbol alone. Equal dates retain stable user order. The nearest event is never promoted into the favorite's large presentation or persisted as an automatic selection.

Deleting or expiring a selected event clears the choice: the panel returns to ordinary compact cards and the idle menu bar returns to Mars. Clearing the star has the same presentation result, including after hiding/reopening or relaunching. Existing valid stored selections are preserved; an absent or invalid selection remains absent after normalization and restart.

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

In an event card, the checkbox, its text and the remaining width of the same subtask row form
one completion control. A click anywhere in that row changes that subtask exactly once; reopening
a completed row uses the same control. Checkbox accessibility and keyboard activation remain
native. Other rows and the checklist disclosure header do not share its activation area. Subtask
text fields in the event editor remain editable and do not become row-completion controls.

Completed subtasks remain visible.

Incomplete subtasks are displayed before completed subtasks.

Stable user order is preserved inside each group.

Completing all subtasks does not complete, archive, or expire the parent event.

The event continues to exist until its own calendar date ends.

### Progress

When subtasks exist, the disclosure header shows completed count over total count. Only when
total > 0 and completed == total, a green SF Symbol checkmark precedes the green `N из N` count.
Use the existing semantic green adapted for Light/Dark and Increase Contrast. The label, chevron,
other header controls and native checkbox rows retain their ordinary colors. The indicator remains
visible when collapsed. Reopening a task or adding an unfinished task restores the ordinary counter.
This is derived presentation, not a saved completion flag, button or parent-event completion state.
It never completes, archives or reschedules the event. Accessibility conveys `все выполнены` on
the existing disclosure button; the decorative checkmark is not a separate accessibility control.

When no subtasks exist, a `0/0` progress state is not shown.

### Collapse state

The subtask list may be expanded or collapsed independently for each event. Its entire disclosure
row is clickable, with a chevron beside `Подзадачи` on the left and `N из M` on the right. Favorite
and edit buttons remain separate controls and do not trigger disclosure.

Collapse state is UI preference state rather than event content.

It is stored separately from `countdowns.json` and restored across normal application restarts.

Expanding and collapsing a checklist uses a short, non-spring transition of height and opacity lasting 200 milliseconds. With Reduce Motion enabled, it switches immediately. Rapid repeated clicks leave the checklist in the state requested by the last click; other events' disclosure states and event data remain unchanged. Collapsed subtasks do not receive input or remain exposed as interactive accessibility content.

## Menu bar

When the timer is idle, only an active explicitly selected favorite supplies the event representation. With no valid favorite, the menu bar displays the Mars application symbol alone, whether the list has events or is empty. It never automatically displays the nearest event.

Its normal event representation contains:

- the event emoji, or the monochrome K1 outline calendar when no additional emoji is stored or the legacy `📅` is stored;
- `Сегодня` for today, `Завтра` for tomorrow, otherwise remaining calendar days with Russian day forms.

The menu-bar Mars uses native vector PDFs for Light and Dark appearance: a neutral planet with a terracotta stripe. Light appearance uses body `#303038` and stripe `#b44e38`; Dark uses body `#f0eee9` and stripe `#ef9b81`. Craters remain transparent. Its colors follow the status button's effective appearance, including live appearance changes while no other state changes. K1 remains a native monochrome template image. Stored event emoji remains unchanged. The application icon preserves the same Mars geometry and colored stripe. Its Default appearance uses a warm light tile `#f5f1e8`, planet `#303038` and stripe `#b44e38`; Dark uses tile `#211c19`, planet `#f0eee9` and stripe `#ef9b81`. The three craters reveal the tile beneath the planet. A system icon catalog provides Default/Dark on macOS 26, alongside compatible legacy renditions and an ICNS fallback. The system icon style may differ from the appearance of application windows.

It does not display:

- event title;
- event date;
- note;
- subtask text;
- subtask completion controls;
- subtask progress.

While the timer is running, its representation temporarily takes precedence and the menu bar displays the system alarm-clock symbol plus the remaining timer value. When the timer is finished but not yet deleted, the menu bar displays the alarm-clock symbol alone. Deleting the timer restores the explicit favorite representation, or Mars alone if there is no active favorite.

When no events exist and the timer is idle, the same Mars symbol remains the entry point. There is no `Countdown` label or zero count. Its tooltip distinguishes an empty list from a nonempty list without a favorite; the status control remains accessible as Countdown Manager.

Opening the mini-panel or desktop window starts one slow, linear, full revolution of the Mars
symbol in the status bar over 12 seconds, then leaves it at its original orientation. Opening again
starts a fresh single turn; ordinary ticks and data refreshes do not. The Dock application icon
always remains static in its new Light/Dark palette, including while the status symbol turns.
The status-bar animation is visible only while the idle status representation is Mars. Selecting
a favorite or starting a timer immediately restores that representation and ends the turn;
clearing it does not resume the interrupted turn. With Reduce Motion enabled, Mars stays static;
enabling it during a turn stops that turn, and turning it off does not start a new cycle.
Completion, Reduce Motion and termination remove the transient status animation. This effect adds
no preference or persisted event state and does not change application activation or Dock presence.

## Empty state

After a successful load with no active events, the whole list header is absent: date, count,
calendar/plus controls and any expanded day-choice row. The 60-point timer and existing 33-point
footer remain in the retained 390 × 600 panel. The free event area centers a current-date calendar
leaf, `Пока нет событий`, and `Выбери день события. Название и детали можно изменить.`
The ordinary Georgia title and warm Light/Dark/Increase Contrast palette are retained.

A 260 × 34 accent `На сегодня` button is followed, 8 points below, by equally wide secondary
`На завтра` and `Выбрать дату` buttons, 32 points high and separated by 8 points. Each starts an
`Новый день` draft using the existing day-creation defaults: Russian weekday title, empty note,
additional emoji and checklist, weather ON, and favorite OFF. The initial dates are today, tomorrow
and tomorrow respectively. The choose-date route uses the existing native editor date field, with a
prompt to select a date. Date changes update the weekday title until its first manual edit; a custom
title is then preserved. No new calendar, persisted data type or automatic Save is introduced.

Today's expiry warning is conditional on retention being off; mutation-time midnight validation remains authoritative. Cancel creates no
event; panel hide/show retains the draft. Hidden/repeated creation actions cannot replace an open
editor. First successful Save restores the existing header/list. Deleting or expiring the last event
returns this empty state, and its calendar leaf follows `Store.today` across midnight/wake/reopen.
Loading, failed reads and persistence recovery are not successful empty lists and expose no empty
creation actions. The nonempty `+` still starts an ordinary untitled event for tomorrow; header and
empty-state day creation share the same weekday title/weather defaults.

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

The user may enable or disable it from settings. If macOS requires approval, settings provides
the existing route to Login Items in System Settings rather than claiming launch at login is
already authorized.

## Persistence

Countdown Manager stores event data locally on the current Mac.

The production event data location is:

`~/Library/Application Support/CountdownManager/countdowns.json`

Attachment metadata is stored with its event; file bytes are stored separately under the sibling
`Attachments` directory. Legacy JSON without `attachments` decodes as an empty collection, and
empty collections are omitted when saving. Attachment JSON contains no source paths or file bytes.
Abandoned imported copies are collected only after successfully reading the event data; a corrupt
event file must never authorize attachment cleanup.

The single timer deadline is stored separately from event data in local application preferences. Timer ticking does not rewrite `countdowns.json` or perform per-second persistence writes.

Stored data must preserve existing supported event content across normal application restarts and compatible application updates.

Existing compatible data from older supported schema versions must remain readable unless an explicit future migration changes that contract.

The optional JSON `showsWeather` boolean defaults to false when absent. True is encoded explicitly;
false is omitted to preserve legacy-compatible ordinary-event files. Saved event content and
identities are retained without assigning weather based on title or migrating existing days.
Weather forecasts and automatic coordinates are not event data.

The optional `usesAutomaticTitle` JSON boolean defaults to false when absent; true is encoded
explicitly, false is omitted. The textual title is also retained for compatible older readers.
Unsupported null or non-boolean mode values fail safely rather than guessing the user's intent.

The optional `keepsAfterDate` JSON boolean defaults to false when absent; true is encoded explicitly,
false is omitted. Null or non-boolean values fail safely. Older versions that do not understand
retention can drop this flag and remove past events and their copies. A downgrade requires a matched
backup of the event JSON and `Attachments/`; it is not a safe way to preserve retained events.

Invalid or corrupted user data must fail safely.

The application must not silently overwrite invalid user data merely to recover from a read failure.

Newer successfully accepted event state must not be replaced later by an older delayed persistence operation.

The technical persistence design belongs in the relevant architecture decision.

## Application updates

An update-enabled distribution uses Sparkle to check a public HTTPS update feed periodically.
Settings provides `Проверить обновления…` and an `Автопроверка` preference; disabling
automatic checks leaves manual checks available. Event and timer use remain available offline.
Updates do not send event content, timer state or a system profile to the update server.

Sparkle presents available updates and manages download, signature verification, installation
and relaunch using its standard interface. The user chooses whether to install; silent automatic
installation is disabled. Both the update archive and the appcast must carry valid Ed25519 signatures.

Before interactive update UI opens, the application hides its retained status panel so update
controls remain accessible. Explicitly reopening the panel during an update returns to the same
editor and running timer; its temporary ordinary window level allows later native update windows
to appear above it. Ending the update session restores the normal panel level without reopening it.

An update restart waits while any event editor is open, event persistence is loading/writing/recovering,
or the timer is running. Downloading does not authorize discarding a later-opened draft or interrupting
a later-started timer. A blocked update remains ready; `Обновление готово · установить…` resumes it
only after a fresh safety check. Safety is checked again when Sparkle requests application termination.
Hiding the panel does not remove an editor's protection. Save/Cancel end the editor session.
A blocked installation explains the current reason and offers `Вернуться к работе`, reopening the
same panel. Finishing that work never retries installation automatically; the ready-update action
is still explicit.

A finished timer can survive update restart with its deadline and finished state intact, without
replaying its sound or completion alert. Explicit user Quit retains its established semantics.
Updates preserve the production bundle identifier and the existing event, timer and preference locations.

Development builds without an explicitly configured feed and public key do not start the updater
or contact a placeholder feed. An updater-enabled first version still needs manual installation;
older versions without Sparkle cannot acquire it automatically. Ad-hoc signing does not provide
Apple notarization or change macOS first-install Gatekeeper trust.

## Privacy

Countdown Manager does not require cloud storage or an online account for normal product behaviour.

User event content, attached file copies and timer state remain local to the Mac. Opening an
attachment in another application gives that application access to the selected copy.

Optional weather requests disclose the selected forecast coordinates to the forecast service,
not event titles, notes, emoji, subtasks, identities or timer state. Automatic device coordinates
are never persisted or logged by Countdown Manager; the manual city selection and global weather switch are local
preferences. Location permission is requested through macOS only when enabled automatic weather
has an eligible event to serve; disabling weather or using a manual city does not request it.
Request coordinates are rounded to two decimal places, roughly an area at kilometre scale.
The service also sees the network IP. [Open-Meteo's privacy terms](https://open-meteo.com/en/terms)
allow server logs containing coordinates and IP information, with deletion after ninety days;
the application's no-coordinate-log rule does not describe the provider's storage.

Diagnostics must not contain private event content such as:

- event titles;
- notes;
- user-selected emoji;
- subtask text;
- attachment names, source paths or file contents.

Technical operational information may be recorded when needed for diagnostics.

Weather diagnostics must not contain request URLs, coordinates, selected city names, event content
or response bodies. Transport errors use numeric URL error codes rather than localized error text
or arbitrary error descriptions, which can include private request details.

## Diagnostics

Countdown Manager maintains local diagnostic information for investigating application behaviour and failures.

Diagnostics may record technical facts such as:

- operation type;
- technical identifiers;
- revision or ordering information;
- timer duration or completion outcome;
- success or failure;
- UI-stall detection.

Weather diagnostics may record the fixed service identifier, a bounded technical result category,
HTTP status, numeric URL error code, elapsed request duration and aggregate counts. Availability
and suppression diagnostics describe state transitions; unchanged refreshes must not produce
repeated state records. They do not change forecast requests, retries, cache lifetime or the UI.

A weather diagnostic snapshot is recorded automatically on application launch, including a launch
after an update, and as normal weather work settles. The user does not need to change weather
settings to start diagnostic collection. `Сохранить диагностику…` records the current snapshot
and opens a native save dialog for a ZIP archive. A snapshot observes current state only: it does
not force a forecast refresh, retry, location request or permission prompt. Automatic repeated
snapshots are bounded by state changes; an explicit diagnostics action may record the same state.

Export is local and explicit; it does not upload or send anything. The ZIP contains redacted current
and, when present, previous journal generations plus a technical summary of app version/build,
macOS version, architecture, time/offset, timer phase, updater state, Store counts/persistence state
and the current weather state. It does not attach event JSON, a preferences dump, filesystem paths,
request details or arbitrary historical error text. Cancelling the dialog writes no archive;
failures remain visible and do not replace an existing destination with an incomplete archive.
The general in-process native-dialog check covers opening, Cancel, reopening and Cancel.
Separate external 1.18.0 acceptance confirmed native Save and inspected the written ZIP after
correcting the diagnostic test's Go to Folder text clearing. Archive creation/redaction also has
deterministic coverage; see `docs/VERIFICATION.md` for the exact build/input-source boundaries.

Journal submission is asynchronous and bounded: it admits at most 512 pending messages with a
4 KiB UTF-8 input budget per message and may drop records under pressure. Diagnostic availability
is best effort and must never block normal app interaction. File access, rotation, OSLog and ZIP
work run on utility queues; production UI paths do not synchronously drain the journal.

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
- overdue-task status (retained past events remain ordinary dated events);
- automatic event rollover;
- independent subtask dates;
- subtask priorities;
- nested subtasks.

These capabilities are product changes. They must not appear incidentally as part of an unrelated technical fix.
