# Countdown Manager — Product

## Purpose

Countdown Manager is a native macOS menu-bar application for tracking today's and future events by calendar day.

The product is intentionally small and quiet. The central concept is an event date and the number of calendar days remaining until that date, including `Сегодня` on the event's date. The application also provides one lightweight countdown timer for short time-based reminders.

Countdown Manager is not a task manager or calendar replacement. Outside the single timer completion alert, it does not provide event or subtask reminder workflows.

The application does not require an account or internet connection for event and timer use.
Optional weather forecasts require a network connection.

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
weather and favorite native checkboxes form a distinct group below it, separated by 13 points.
Subtasks follow a separate section, with room prioritized for their editable text. The form scrolls
while Delete, Cancel and Save share one fixed bottom action row; deletion still requires an inline
confirmation. The field is a selection control, not an editable text input. The picker is initially
collapsed. Activating it reveals eight compact presets and a `Все значки` action; activating it
again collapses the picker. Opening or closing it preserves every draft field.

`Все значки` reveals the larger inline catalog organized into five named sets: `Общие`, `Дети`, `Работа`, `Транспорт` and `Праздники`. Each set is a six-row/eight-column page, fitting the editor's available inner width. The current set name is shown above conventional previous/next controls with page dots; horizontal drag/swipe may also change sets. The first set keeps the compact presets as its top row. Choosing any emoji or clearing the selection resets catalog navigation and collapses the entire picker. New selections come from the provided catalog; an existing stored valid emoji outside that catalog remains displayable and may be preserved until the user selects another one.

Picker disclosure uses a 200-millisecond non-spring height and opacity transition. The chevron communicates expansion, and changing the selected value may use a brief opacity transition. With Reduce Motion enabled, transitions are immediate. Rapid repeated requests finish in the state requested by the last action. Collapsed picker content does not receive input or remain exposed as interactive accessibility content.

Event deletion uses an explicit inline confirmation with a cancel action. Launch at login, diagnostics and Quit remain accessible through ordinary controls. A dedicated Restart action is removed; the application can be quit and launched normally.

Use ordinary controls inside the panel. The event interface uses a warm ivory palette with a terracotta accent and serif titles, with a related warm dark appearance and an Increase Contrast adaptation. The featured event has a larger calendar leaf on its right; other events have smaller calendar leaves on their left. The featured event is the selected favorite, or the nearest event starting with today when no favorite is selected. Each leaf shows the event's actual month and day, without a leading zero. A selected additional emoji appears immediately before the event title. Empty emoji and legacy `📅` are omitted from the list because the leaf already conveys the date; legacy stored values remain available in the editor. When no favorite is selected, the featured block is labelled `Ближайшее событие` and every star is unfilled.

Event cards express their civil-day distance as `Сегодня`, `Завтра`, then `Через N дней`
with correct Russian day forms. The exact date and event title remain visible and unchanged.
A featured card uses one 21-point Georgia line below the date: green for today and the
existing terracotta accent for future days. Secondary metadata is ordered `date · relative label`,
including today; only today's relative label is green. The menu-bar count keeps its existing
compact numeric format. Labels are derived from the current civil day; expiry rules are unchanged.

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

## Settings

Settings is an internal screen in the same retained 390 × 600 panel. The 60-point timer strip
remains above the 540-point manager area on both the list and settings screens; timer actions
remain available. Settings navigation does not open another window, sheet or popover. The explicit diagnostic
export action uses the native macOS save dialog.

The list footer remains a single compact row: `Хранится на этом Mac`, a small settings gear
immediately before `Выйти`, and `Выйти`. The gear has a 14-point visible symbol and a 22-point
activation area. The header retains its existing calendar and `+` creation controls.

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

Settings changes apply immediately without Save/Cancel. `Назад` returns to the same list and its
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
- an optional note;
- a calendar date;
- an optional additional emoji;
- zero to ten subtasks;
- an optional weather-display choice.

Multiple events may use the same date.

Event dates and countdowns use calendar-day semantics rather than elapsed-second calculations.

### Creating an event

A new event may use today's date or a future date. The ordinary header `+` initially selects
tomorrow; empty-state creation offers today, tomorrow or the native date-selection route.

Past dates cannot be selected or saved. Date validation uses the current calendar day when saving, including when a draft remains open across midnight.

Saving the first event does not select a favorite automatically. The favorite choice in a new draft is initially off.

Ordinary event and day drafts start without an additional emoji. The editor offers `Без значка` to clear a selected emoji; Save accepts this empty choice. Editing an existing event preserves its stored emoji until the user changes or clears it.

Changes entered in the editor do not become event data until the user explicitly saves them.

### Creating a day

The header calendar control, labelled `Создать день`, reveals inline `Сегодня`, `Завтра` and `Выбрать дату` choices inside the event list. The existing `+` control still opens ordinary event creation directly. These choices do not open an action popover.

All day choices open the existing editor as `Новый день`. `Сегодня` initially selects today; `Завтра` and `Выбрать дату` initially select tomorrow. `Выбрать дату` asks the user to choose today's date or a future date in the ordinary date field. A day draft starts without an additional emoji, with the Russian weekday name for its selected date, an empty note and no subtasks. Its `Показывать погоду для этого дня` checkbox is initially on; ordinary `+` drafts start with it off.

While the title has not been manually edited, changing the date updates the weekday title. After a manual title edit, later date changes preserve that custom title. All ordinary event fields remain editable.

Opening a day draft creates no persisted event. Save creates an ordinary event with the existing date, validation, primary-selection and expiry rules. Multiple events on the same date remain allowed. A repeated creation request while an editor is already open preserves that editor and its input rather than replacing it. Hiding and showing the panel also preserve the draft.

This is a single-day creation shortcut; it does not create a week or store reusable templates.

### Editing an event

An existing event may be edited while it is scheduled for today.

An active event may be moved to today's date or a future date. An event occurring today may also remain on today's date.

Editing does not change durable event data until the user explicitly saves.

`Показывать погоду для этого дня` is available in the editor for new and existing events. Save
persists this choice; Cancel keeps the previously saved value. Changing a title or date does not
infer or reset the choice. Existing events, including weekday-titled events, remain opted out
unless the user explicitly changes them. No title-based migration or separate persisted day type
is introduced.

### Today

An event remains active and available throughout its entire calendar date.

On that date, its countdown is represented as `Сегодня`.

The event remains editable and removable during that day.

When an editor's selected date is today, it shows `После окончания дня событие будет удалено, включая незавершённые подзадачи.` This applies to ordinary event creation, day creation and editing an existing event.

### Expiry

After an event's calendar date has ended, the event expires automatically.

Expired events are removed rather than moved into an archive.

There is no overdue state and no automatic rollover.

Incomplete subtasks do not prevent event expiry.

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

Today's expiry warning and mutation-time midnight validation are unchanged. Cancel creates no
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

The single timer deadline is stored separately from event data in local application preferences. Timer ticking does not rewrite `countdowns.json` or perform per-second persistence writes.

Stored data must preserve existing supported event content across normal application restarts and compatible application updates.

Existing compatible data from older supported schema versions must remain readable unless an explicit future migration changes that contract.

The optional JSON `showsWeather` boolean defaults to false when absent. True is encoded explicitly;
false is omitted to preserve legacy-compatible ordinary-event files. Saved event content and
identities are retained without assigning weather based on title or migrating existing days.
Weather forecasts and automatic coordinates are not event data.

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

User event content and timer state remain local to the Mac.

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
- subtask text.

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
The automated native-dialog check currently covers opening, Cancel, reopening and Cancel;
physical confirmation of Save is not yet established. Archive creation/redaction has separate
deterministic coverage; see `docs/VERIFICATION.md` for the acceptance boundary.

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
- overdue events;
- automatic event rollover;
- independent subtask dates;
- subtask priorities;
- nested subtasks.

These capabilities are product changes. They must not appear incidentally as part of an unrelated technical fix.
