---
name: Countdown Manager
description: Warm calendar leaves and quiet native controls for dated events.
colors:
  terracotta: "rgb(71.8% 27.8% 17.3%)"
  terracotta-dark: "rgb(96% 61% 50%)"
  terracotta-contrast: "rgb(63% 17% 10%)"
  terracotta-dark-contrast: "rgb(100% 75% 63%)"
  ivory-canvas: "rgb(98% 96% 93%)"
  warm-dark-canvas: "rgb(13% 11% 10%)"
  paper-surface: "rgb(100% 98% 95%)"
  warm-dark-surface: "rgb(16% 13% 11%)"
  warm-dark-elevated: "rgb(20% 16% 13%)"
  contrast-paper: "#ffffff"
  ink: "rgb(19% 15% 13%)"
  ink-dark: "rgb(95% 90% 83%)"
  secondary-ink: "rgb(45% 36% 29%)"
  secondary-ink-dark: "rgb(76% 69% 60%)"
  timer-surface: "rgb(95% 92% 87%)"
  timer-surface-dark: "rgb(18% 15% 12%)"
  rule: "rgb(68% 55% 36% / 30%)"
  rule-dark: "rgb(49% 40% 31% / 50%)"
  rule-contrast: "rgb(36% 28% 22%)"
  rule-dark-contrast: "rgb(75% 68% 59%)"
  accent-ink: "rgb(70% 20% 12%)"
  accent-ink-contrast: "rgb(57% 20% 12%)"
  today: "rgb(0% 39% 23%)"
  today-dark: "rgb(40% 85% 65%)"
  today-contrast: "rgb(0% 32% 23%)"
  today-dark-contrast: "rgb(55% 94% 75%)"
  finished: "rgb(64% 32% 0%)"
  finished-dark: "rgb(100% 70% 36%)"
  finished-contrast: "rgb(51% 24% 0%)"
  finished-dark-contrast: "rgb(100% 82% 54%)"
  warning: "rgb(50.6% 33.3% 11%)"
  warning-dark: "rgb(88.2% 71.4% 47.8%)"
  warning-contrast: "rgb(40% 23% 5%)"
  warning-dark-contrast: "rgb(100% 84% 63%)"
  completed: "rgb(48% 44% 40%)"
  completed-dark: "rgb(50% 46% 42%)"
  completed-contrast: "rgb(38% 35% 32%)"
  completed-dark-contrast: "rgb(53% 48% 43%)"
typography:
  display:
    fontFamily: "Georgia"
    fontSize: "32pt"
    fontWeight: 400
    letterSpacing: "-0.5pt"
  headline:
    fontFamily: "Georgia"
    fontSize: "23pt"
    fontWeight: 400
    letterSpacing: "-0.6pt"
  title:
    fontFamily: "Georgia"
    fontSize: "21pt"
    fontWeight: 400
  countdown:
    fontFamily: "Georgia"
    fontSize: "21pt"
    fontWeight: 400
  body:
    fontFamily: "system-ui"
    fontSize: "13pt"
    fontWeight: 400
  event-title:
    fontFamily: "system-ui"
    fontSize: "14pt"
    fontWeight: 600
  label:
    fontFamily: "system-ui"
    fontSize: "11pt"
    fontWeight: 400
  timer:
    fontFamily: "system-ui"
    fontSize: "23pt"
    fontWeight: 600
    fontFeature: "tabular-nums"
rounded:
  input: "4pt"
  leaf: "5pt"
  timer-button: "6pt"
  card: "8pt"
spacing:
  tight: "4pt"
  label-gap: "6pt"
  control-gap: "8pt"
  list-gap: "10pt"
  card-inset: "12pt"
  panel-inset: "16pt"
components:
  event-card:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  event-card-dark:
    backgroundColor: "{colors.warm-dark-surface}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  creation-button:
    backgroundColor: "{colors.terracotta}"
    textColor: "{colors.contrast-paper}"
    rounded: "{rounded.card}"
    size: "31pt"
  timer-start:
    backgroundColor: "{colors.terracotta}"
    textColor: "{colors.contrast-paper}"
    rounded: "{rounded.timer-button}"
    size: "32pt"
  icon-selection-field:
    backgroundColor: "{colors.ivory-canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.input}"
    height: "38pt"
  featured-calendar-leaf:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.leaf}"
    width: "54pt"
    height: "65pt"
  secondary-calendar-leaf:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.input}"
    width: "42pt"
    height: "51pt"
---

# Design System: Countdown Manager

## Overview

**Creative North Star: "Warm Calendar Leaves"**

Countdown Manager uses warm paper and terracotta calendar leaves to make a small dated-event utility feel tangible. Georgia gives event names and dates an editorial character; compact native system text keeps actions, settings, and checklists legible. The warm dark appearance preserves the same hierarchy through related surfaces rather than applying a neutral black theme.

This is a record of the completed native macOS implementation, adapted from the user-approved imported HTML and corrected icon-field reference. It is not a seed or a web implementation specification. SwiftUI and AppKit remain authoritative for native controls, focus, accessibility, and platform metrics.

**Key Characteristics:**
- Warm ivory, terracotta, and related warm dark surfaces.
- Georgia calendar numerals and event headings with native system controls.
- A compact retained panel with a distinct timer strip and fixed service actions.
- Calendar leaves provide the signature; quiet tonal surfaces group events and checklists.

## Colors

A warm ivory and terracotta palette is paired with warm brown dark surfaces; green and ochre carry specific time states rather than a second decorative identity. Frontmatter preserves the exact normalized sRGB values used in Swift as CSS percentages, including stroke alpha. The light/dark and Increase Contrast branches are paired semantic roles, not a generated tonal scale.

### Primary

- **Terracotta:** creation controls, selected timer presets, calendar month bars, focus outlines, and favorite stars. Dark mode uses its lighter counterpart; Increase Contrast selects the explicit contrast branch.
- **Accent Ink:** the future-day relative label and selected preset text. Light mode has its own darker text color; dark mode reuses the accent.

### Secondary

- **Today Green:** today's state and count, using the corresponding appearance and contrast branch.
- **Finished Ochre:** timer completion status; the completed timer strip overlays this color at 10% opacity.
- **Warning Ochre:** today's editor expiry explanation, separate from destructive or invalid state red.

### Neutral

- **Ivory Canvas / Warm Dark Canvas:** panel background and fixed service footer.
- **Paper Surface / Warm Dark Surface:** event cards, calendar leaves, idle timer, and the inline emoji catalog. Increase Contrast makes light surfaces white; elevated dark surfaces use the warmer raised tone.
- **Timer Surface:** running and finished timer strip, in both appearances.
- **Ink / Secondary Ink:** primary content and supporting date, count, hint, and service text.
- **Rule:** dividers and outlined controls. Increase Contrast uses opaque, stronger rules and adds explicit event-card outlines.
- **Completed Neutral:** completed checkbox marks; completed content stays readable and directly actionable.

Native semantic red is used for validation and errors; do not replace it with an invented fixed RGB token. Accent fills use accent at 10% opacity normally and 22% in Increase Contrast; accent borders use 50% normally and full opacity in Increase Contrast.

## Typography

**Display Font:** Georgia, resolved by macOS.
**Body Font:** the native macOS system font through SwiftUI `.system`.
**Label/Mono Font:** system text; timer numerals and preset values use monospaced digits rather than a separate font.

**Character:** restrained serif emphasis sits within a functional native interface. Font sizes in frontmatter are macOS points, not CSS pixels; SwiftUI owns default line heights and native control metrics.

### Hierarchy

- **Display:** featured calendar day (32 points); secondary leaf day uses 25 points, both with compact negative tracking.
- **Headline:** featured event title (23 points), negative tracking, and up to two lines. Empty-state heading uses 24-point Georgia.
- **Title:** editor and settings headings (21 points).
- **Countdown:** the mini-panel's full featured relative label, `Сегодня`, `Завтра`, or `Через N дней`, in 21-point Georgia. Today uses green; future days use accent ink.
- **Body:** settings use 13-point system text; form content and checklist text mostly use 12 points; secondary event names use 14-point semibold.
- **Label:** metadata and secondary labels mostly use 11 points. Current-date heading is 15-point semibold. The functional featured-state label uses 10.5 points; small service text uses 10 points. Calendar month labels use 10-point semibold on featured leaves and 9-point semibold on secondary leaves, with tracking of 0.7 and 0.5 points respectively.
- **Timer:** running countdown uses 23-point semibold tabular numerals; preset values use 11-point medium or semibold when selected.

**The Calendar Leaf Rule.** Use the leaf to carry the actual month and day; the larger featured leaf sits on the right and secondary leaves on the left.

**The Native Control Rule.** Preserve native text entry, checkbox, date, menu, focus, disabled, and keyboard behavior when extending the interface.

## Layout

The native status-item panel is retained at 390 × 600 points: a 60-point timer strip above a 540-point manager area. List, editor, and settings replace the internal manager screen. There are no responsive web breakpoints; content scrolls within the native panel.

The list starts with the current date and event count, then the selected favorite if any, followed by ordinary events. Without a favorite, all cards remain compact. The header has 16-point horizontal insets and 12-point vertical padding. The scrolling list uses 12-point side insets, 10-point gaps, and 12-point card padding. The service footer is fixed below the list at 33 points high with 18-point side insets.

Editor and settings headings occupy a 49-point header with 16-point side insets. The editor's form scrolls while its 58-point bottom action row stays fixed. Form content reserves a 4-point focus-ring inset and separate scroll-indicator clearance. Settings uses 16-point group spacing, 12-point internal group spacing, and 16-point side insets. The icon field is full-width and 38 points high; weather and favorite checkboxes form the next distinct group after a 13-point gap.

The desktop window uses a separate browser/details split. Its icon-only native
segmented control switches collection/grid and feed/list, retaining names and hover help.
One favorite stays above month-and-year sections; empty months and duplicate favorite rows are
omitted. Section headings use 20-point Georgia, with 24-point section gaps. Grid cards keep a
180-point minimum width and 12-point gaps; list rows use 10-point gaps. A short 150 ms
ease-in-out reflows the same ordinary event identities without scaling text, spring effects or
fading the entire browser. Calendar, title and metadata remain persistent visual elements;
text reflows inside clipped moving containers rather than animating individual glyph positions.
Reduce Motion makes mode changes immediate. The desktop footer
contains navigation and settings, not timer controls; the compact panel's timer is unchanged.

Desktop checklist completion/reopening animates only the persistent task rows with a 150 ms
ease-in-out; Reduce Motion disables this movement. It does not animate the entire inspector or
disable sibling controls. Under `Впереди`, the desktop overview places the current date and eligible
forecast for today on the same metadata line. The date position, line height and content below
remain stable when weather is absent, disabled or loaded; absent weather exposes no placeholder.
Ordinary feed rows align the calendar with the top of the title; their remaining-day label
sits at the upper right. Date and eligible weather share one line, with temperature after
the date, and checklist progress/paperclip count share one horizontal summary. Rows use a
compact height without a separate weather slot or vertically stacked counts. The featured
favorite places date and weather inline on a full-width row below its title/calendar identity.
Ordinary grid cards retain separate date/weather rows with a reserved
16-point weather slot, including when the forecast is absent. That empty slot contains no
visible or accessible placeholder. Mini-panel layouts are unchanged.

The desktop detail action group uses neutral primary ink for the outline star, pencil and trash.
Only a selected, filled favorite star uses the accent color. Color communicates favorite state,
not a permanent difference between otherwise equal icon actions; mini-panel controls are unchanged.

## Elevation & Depth

Depth is primarily tonal. Event cards are quiet paper surfaces without general drop shadows; Increase Contrast adds a one-point outline. Thin rules separate timer, headings, settings groups, and fixed action regions. Calendar leaves retain a restrained rotation (3 degrees featured, 2 degrees secondary), without a drop shadow. Their one-point outline is inset within the clipped silhouette to keep the edge clean.

**The Paper Depth Rule.** Use tonal surfaces for event grouping and reserve the slight rotation for calendar leaves; do not add blurred shadows to their edges.

## Shapes

Cards use softly squared corners (8 points), fields use tighter corners (4 points), featured calendar leaves and preset selection backgrounds use 5 points, and timer-start buttons use 6 points. Secondary leaves use 4 points. Preserve these roles rather than turning every control into a pill. Calendar leaves clip their terracotta month strip and paper numeral area to one silhouette.

## Components

### Buttons

Creation is a compact terracotta square (31 × 31 points, 8-point corners); timer start is 32 × 32 with 6-point corners. Both use light content in light appearance and dark content against the lighter dark-mode accent. Favorite and edit actions use SF Symbols within 28-point targets. Save and Cancel keep native bordered-prominent and bordered button styles, large control size, default/cancel shortcuts, and platform focus and disabled states. Plain service actions remain visually quiet. Custom plain buttons do not add an invented universal hover animation; native keyboard focus remains available.

### Timer Presets

Seven fixed durations share a 32-point high row with 2-point gaps. The selected 5-point-corner surface carries accent tint, a one-point rule, and semibold text. A two-point inset focus outline distinguishes keyboard focus. Left/right commands move selection. The selection background slides with ease-in-out over 180 ms; labels update immediately. Reduce Motion makes selection immediate.

### Cards / Containers

In the mini-panel, each dated event and its checklist share one card. Only the selected favorite is featured: Georgia title, larger right-aligned calendar leaf, and a separate relative-label line. Eligible weather follows the full date beneath the title, separated by a middle dot; the relative-label line contains no duplicate forecast. When no forecast is eligible or event weather is disabled, the forecast and its separator are absent. Ordinary cards put a smaller leaf on the left and use compact date/count/weather metadata. Notes and checklists remain inside the same event block; individual subtask rows have no horizontal separators. Desktop ordinary grid cards retain separate date and reserved weather rows; feed rows, the featured favorite and compact details use inline date/weather as described above.

### Inputs / Fields

Title, note and subtask text fields use the native rounded-border bezel and native focus ring only. Do not overlay a second border or accent focus outline on these controls. The separate emoji selection control owns its custom outline. Date selection stays a native field-style DatePicker; weather/favorite and settings toggles stay native checkboxes. Native focus, selection, accessibility, validation, and disabled presentation remain authoritative.

The optional note field is always visible, including when empty. Its label is `Заметка · необязательно`, its placeholder is `Пара слов о событии`, and its counter starts at `0/150`. The label and counter use native caption and caption2 roles; the multiline native text field inherits the editor’s 13-point body text, reserves three lines, grows to six, then scrolls vertically. New notes accept up to 150 graphemes. Existing longer notes remain fully visible and may be preserved or shortened under the [saved-note allowance in PRODUCT.md](docs/PRODUCT.md#primary-interface). There is no note disclosure action.

The `Значок` field is an outlined selection control with label, selected emoji or `Без значка`, disclosure chevron, and a separate clear target when selected. Clearing does not disclose the picker. Its inline picker uses eight compact presets followed by the larger catalog. Disclosure uses height and opacity over 200 ms; selected-value opacity takes 120 ms. Reduce Motion makes both immediate. The inline catalog uses the same paper surface and border language rather than a separate window.

### Attachments

Desktop details, mini-panel cards and the shared editor order their note, `Подзадачи` and
`Вложения` content in that sequence. Subtask and attachment headings share readable semibold
weight and primary ink; the desktop checklist label is `Подзадачи`, not `Подготовиться`.
Desktop details use 24-point content insets and 20-point section spacing. A wrapping 27-point
Georgia title sits beside the smaller calendar leaf; a full-width 12-point date/eligible-weather
line follows, then the 22–23-point relative label. Forecast arrival does not introduce another row.
The saved empty note section is hidden; editor note entry and the empty checklist message remain.
Saved attachment sections disappear when empty; the editor still offers Add at zero.
Desktop saved summaries use a left-aligned two-column shelf, up to four files, with 10-point gaps
and a maximum width of 490 points. Preview canvases are 88 points high; filenames reserve two
12-point lines above secondary import-time size. Mini summaries use the first three files in
three equal columns, 8-point gaps and 68-point-high canvases, with two-line compact filenames.
A single file uses only the first column. Whole tiles are native buttons; canvas geometry remains
fixed through loading/failure. The bounded raster request must fit the shelf rather than enlarge
the old 44-point thumbnail. All-files rows retain 44-point desktop / 36-point mini previews;
the shared editor retains 36 points. Photos use a thumbnail,
PDFs show the whole first page within that area, and movies show one static frame with a small
video indication. Other formats also request a best-effort native preview; unavailable or failed
previews use a file-type fallback. The reserved
area stays fixed during loading and failure. The whole tile or row remains one explicit preview action;
the decorative preview adds no separate keyboard focus or playback control.
Above four desktop files or above three mini files, `Показать все N` opens the complete bounded
searchable library. Saved order is unchanged. Desktop uses the shared
native sheet with the simple header `Вложение` at left and a cross at right, with no
header count or Back button. It shares the desktop Settings dismissal pattern: the cross,
`Escape`, or the surrounding dimmed backdrop closes it. The backdrop consumes the click
without selecting a background event, while the pane's empty interior does not dismiss it.
The mini-panel keeps its internal screen with `Вложения` and the same plain left-chevron Back
control as its Settings screen, also without a header count. Both footers show `Файлов: N` for an empty trimmed query and `Найдено: X из N` while
searching. Search, clear and a no-results message stay within that surface. It has its own scrolling, and closing/Back returns to the same event/context.
The library is read-only apart from explicit file opening; editing stays in the shared editor.
Its filename search does not change file order or event data, and resets for a different event.
The shared editor keeps its full editable list and 36-point previews before Save and after
reopening. Preview loading/failure does not change the row area or disable editing.
Editor symbols occupy a fixed 18-point-wide column; filenames and size labels align across
PDF, image, movie and other file types instead of following each SF Symbol's intrinsic width.
Saved web links follow the same mini-panel disclosure family as attachments: a fixed-width
chevron, 12-point semibold primary-ink heading, trailing neutral count and one full-width click
target. Start collapsed; retain the mounted session's state on hide/show. Collapsed link rows are
removed from interaction and accessibility. Desktop links remain an expanded detail section;
no mini-panel disclosure is copied into the desktop. Its expanded heading has the same trailing
neutral count and native link symbol as desktop attachments' count/paperclip. Checklist progress,
attachment count and link count in details all use value then symbol in one trailing column. An empty saved links section is absent.
The editor uses the existing SF Symbol `trash`, native rounded fields, and separated Add spacing.

The mini-panel uses a collapsible attachments section inside the same event card. Its disclosure
rotates one fixed chevron, as subtasks do; expanding or collapsing must not move the heading
or count horizontally. Both surfaces
use the event's pencil as their sole editor entry. Saved desktop sections contain no
`Изменить список…`, `Добавить подзадачи…`, `Добавить заметку` or attachment add/change button,
including empty sections. Direct subtask checkboxes, file opening and `Показать все N` remain.
Attachment rows can be added or removed in the shared editor before Save, with
Cancel preserving saved files. Long names truncate with their full name available as help.
Saved files first open a large quick preview; a separate `Открыть в приложении` action launches
their default application. Desktop reuses its native sheet; mini uses an internal 390 × 540 screen
with its usual plain Back chevron. Both use a Georgia `Вложение` heading, filename and one `i из N`
position, flexible native preview canvas and fixed previous/next/external-open controls.
Arrows traverse the entire event in saved order, without wrap; first/last disable the relevant
arrow. Closing the top view returns to its originating event or mounted library/query.
The desktop backdrop consumes its input and uses the same top-view close behavior as the cross.
Missing files retain filename/navigation and an unavailable state; native unsupported-file fallback
keeps external-open available. Videos do not autoplay.
Only the editor and deletion confirmation explain that copied attachments are deleted with
the event after its date while originals remain untouched. Saved summaries and file libraries
do not include that warning. Import progress and errors use native, readable controls.
The editor counter is `N/15`: Add is disabled at 15 or above with a visible explanation,
and removing to 14 enables one new file immediately. Oversized picker batches report remaining
capacity and add nothing. Legacy collections above 15 are displayed in full, preserve their
files and allow removal/unrelated edits; their counter must not imply corruption or force truncation.

Desktop browser cards also show a neutral 11-point paperclip/count summary only when attachments
exist, separately from the user's emoji. Ordinary grid cards stack it below checklist progress
inside the existing status host, so narrow cards can fit both. Feed cards and the featured favorite
use one compact status row. Zero attachments add neither a visible symbol nor an accessible zero state.
The saved-link indicator follows this same status family: system `link`, neutral 11-point medium
count, no zero placeholder. Grid cards stack it below file count; feed and favorite include it in
the same horizontal status row. It is a summary rather than another interactive control.
All three desktop browser summaries use number/progress before the SF Symbol, tabular digits,
a 6-point internal gap and an 18-point symbol column. In grid cards the symbol columns align at
the right; favorite/feed retain the value-symbol order in their common status row. Detail section
headers reuse the same value-symbol metadata style. Mini-panel disclosures keep their own treatment.



The featured desktop favorite places date and forecast inline on their own full-width row
below title/calendar identity. This preserves room for both in a narrow browser pane; ordinary
collection-grid metadata keeps its existing layout.

### Material intake

Saved event drop targets use the existing 8-point event silhouette, accent tint and a stationary
2-point accent outline only while targeted. They add no resting upload container or add button to
saved material sections. Number/symbol summaries and mini disclosure state remain unchanged.
The context menu adds `Вставить текст как вложение…` without changing the star/pencil/trash family.

Text composition follows the shared editor: 21-point Georgia title in a 49-point header, 16-point
insets, native rounded filename field, a scrolling 13-point system text editor and a fixed 58-point
Save/Cancel-family action row. Its content has no note-length limit. Desktop reuses its native sheet;
mini uses the retained 390 × 540 manager surface beneath the timer. The existing event editor stays
mounted and inactive while its nested text composer is visible. Native text editing and Paste remain
available. Saved-event additions add no status row, Undo button or replacement toast. The primary
Create action and existing editor Save share `auroraPrimaryAction()` so native button style, size,
Aurora tint, Increase Contrast branch, foreground and typography cannot drift between them.

### Navigation

The mini-panel's fixed list footer carries local-storage reassurance, an `Открыть основное окно` button, a small settings gear, and Quit. The window button opens or brings forward the retained desktop window. The gear symbol is 14 points in a 22-point activation area. Mini-panel settings has an explicit back control and a Georgia heading. The desktop settings pane instead has its Georgia heading on the left and an `xmark` close control on the right; Escape and backdrop clicks also dismiss it. Settings groups are functional labels with native controls; update and diagnostic rows are actions without navigation arrows. Inactive list content is removed from interaction and accessibility while the editor or settings is active.

Desktop Settings, file libraries and create/edit share one native SwiftUI sheet mechanism,
including system appearance and opening/closing animation. macOS owns timing and Reduce Motion.
The underlying event interface remains inactive until native dismissal finishes. Settings/files
close through their cross, Escape or an outside click on parent content; editor dismissal
retains its explicit Save/Cancel policy. Diagnostic Save is nested under Settings and blocks
Settings dismissal while export is active.

### Mars identity and opening motion

The Dock icon uses the status-bar Mars geometry and body/stripe colors. Light has tile
`#f5f1e8`, planet `#303038` and stripe `#b44e38`; Dark has tile `#211c19`, planet `#f0eee9`
and stripe `#ef9b81`. The stripe is colored and the three craters reveal the tile. Status-bar
Mars has no tile and retains transparent craters; its colors follow its effective appearance.
System icon styling remains separate from the application's window theme.

Opening the mini-panel or desktop starts one full, linear revolution of the status-bar Mars
symbol over 12 seconds, then stops at the original orientation. The Dock icon always stays static
in its new palette; the opening gesture does not replace or animate its artwork. The status symbol
rotates only while it displays idle Mars; favorite and timer presentations interrupt it without
resuming that turn. Each later opening can start a fresh turn, with no loop or restart from ordinary
updates. Reduce Motion keeps Mars static and stops an active turn; disabling it does not start motion.
Completion and cancellation restore ordinary status presentation; no new setting or saved event state
belongs to this effect.

### Calendar Leaves

A real month label sits in a terracotta strip above the Georgia day numeral, without a leading zero. The strip fills the top edge and rounded upper corners without an uncolored inset. Featured leaves measure 54 × 65 points; secondary leaves measure 42 × 51. The slight rotation and clean outline make this the signature material gesture, without a shadow. In the mini-panel, optional event emoji belongs immediately before the event title. In the desktop collection, feed, favorite cards and details, it belongs in the secondary date line, with no reserved icon space when absent. Empty and legacy calendar emoji are omitted from these event presentations because the leaf already carries the date; stored values remain available in the editor.

## Do's and Don'ts

### Do:

- **Do** use the paired light and dark semantic colors from AuroraInstrument, including Increase Contrast adaptations.
- **Do** preserve Georgia for featured event titles, calendar numerals, and internal screen headings.
- **Do** keep focus rings visible within scrolling forms and preserve native checkbox and date controls.
- **Do** respect Reduce Motion and keep the timer and fixed action rows available while forms scroll.
- **Do** distinguish the icon selection field from text entry and keep its clear action separate from disclosure.

### Don't:

- **Don't** replace semantic icons with text glyph approximations in production controls.
- **Don't** introduce panel motion or forced focus transitions into ordinary navigation.
- **Don't** make every event equally prominent; retain featured and secondary calendar-leaf sizes.
- **Don't** promote illustrative HTML previews in the sidecar into native control specifications.

Documentation boundary: extracted from `AuroraInstrument.swift`, `Views.swift`, `SettingsView.swift`, `CountdownTimer.swift`, and the supporting presentation constants; `docs/PRODUCT.md` supplies the accepted native behavior. The approved imported HTML establishes visual authority, while current Swift source establishes token values. Native captures were reviewed by the implementation and independent review passes; this document pass does not claim a separate capture run. The sidecar's HTML/CSS are illustrative light-appearance translations for a design panel, not runtime evidence or pixel-equivalent AppKit rendering. No pre-existing defect is canonized here.


## Executable native design contract

The accepted app identity is `native-warm-calendar-v1`, independent of the application's release
number. `Resources/NativeDesignContract.json` records deployment and linked compatibility plus the
required native appearance matrix. `AuroraInstrument.swift` owns the actual colors/tokens and shared
primary, secondary and symbol-action components. Use `auroraPrimaryAction()` for editor Save and
text-attachment Create, `auroraSecondaryAction()` for their Cancel actions, and `AuroraSymbolAction`
for the existing event star/pencil/trash family. Toolbar Event and Create-day use
`auroraToolbarAction()` and `AuroraToolbarLabel`; the date menu explicitly uses native
`menuStyle(.button)`, hides the framework indicator and places the standard neutral `chevron.down`
in that shared label. It retains its existing today/tomorrow/date choices without a second action. Surface-specific native styles, targets and state
semantics remain explicit; sharing a component is not authority to change a control's behavior.
Existing material headings, summary labels, mini disclosures and native fields keep their current
named owners. The inventory in `docs/qa/native-component-families-2026-10-28.json` maps these families.

Builds explicitly retain the accepted linked-on-or-after compatibility metadata 13.0 instead of
inheriting a different visual branch from `SDKROOT` or the toolchain. The actual compiler headers
SDK may be newer and is recorded separately; this is not described as compiling with SDK13 headers.
`build.sh` verifies contract/authority hashes, native load commands and signatures and embeds
`NativeBuildProvenance.json`. A release version change does not change this design contract.

Source/build gates catch component and provenance drift; they cannot approve a new product mechanic
or certify rendered pixels. Changed native UI is reviewed against accepted siblings in Light/Dark
and standard/Increase Contrast. A/B captures must name the actual build and rendering method.
