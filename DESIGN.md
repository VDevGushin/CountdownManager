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
    fontSize: "27pt"
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
- **Accent Ink:** the remaining-day numeral and selected preset text. Light mode has its own darker text color; dark mode reuses the accent.

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
- **Title:** editor and settings headings, plus featured `Сегодня` (21 points).
- **Countdown:** featured remaining-day numeral (27 points).
- **Body:** settings use 13-point system text; form content and checklist text mostly use 12 points; secondary event names use 14-point semibold.
- **Label:** metadata and secondary labels mostly use 11 points. Current-date heading is 15-point semibold. The functional featured-state label uses 10.5 points; small service text uses 10 points. Calendar month labels use 10-point semibold on featured leaves and 9-point semibold on secondary leaves, with tracking of 0.7 and 0.5 points respectively.
- **Timer:** running countdown uses 23-point semibold tabular numerals; preset values use 11-point medium or semibold when selected.

**The Calendar Leaf Rule.** Use the leaf to carry the actual month and day; the larger featured leaf sits on the right and secondary leaves on the left.

**The Native Control Rule.** Preserve native text entry, checkbox, date, menu, focus, disabled, and keyboard behavior when extending the interface.

## Layout

The native status-item panel is retained at 390 × 600 points: a 60-point timer strip above a 540-point manager area. List, editor, and settings replace the internal manager screen. There are no responsive web breakpoints; content scrolls within the native panel.

The list starts with the current date and event count, then the selected favorite if any, followed by ordinary events. Without a favorite, all cards remain compact. The header has 16-point horizontal insets and 12-point vertical padding. The scrolling list uses 12-point side insets, 10-point gaps, and 12-point card padding. The service footer is fixed below the list at 33 points high with 18-point side insets.

Editor and settings headings occupy a 49-point header with 16-point side insets. The editor's form scrolls while its 58-point bottom action row stays fixed. Form content reserves a 4-point focus-ring inset and separate scroll-indicator clearance. Settings uses 16-point group spacing, 12-point internal group spacing, and 16-point side insets. The icon field is full-width and 38 points high; weather and favorite checkboxes form the next distinct group after a 13-point gap.

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

Each dated event and its checklist share one card. Only the selected favorite is featured: Georgia title, larger right-aligned calendar leaf, prominent countdown, and weather beside the countdown. Ordinary cards put a smaller leaf on the left and use compact date/count/weather metadata. Notes and checklists remain inside the same event block; individual subtask rows have no horizontal separators.

### Inputs / Fields

Title, note and subtask text fields use the native rounded-border bezel and native focus ring only. Do not overlay a second border or accent focus outline on these controls. The separate emoji selection control owns its custom outline. Date selection stays a native field-style DatePicker; weather/favorite and settings toggles stay native checkboxes. Native focus, selection, accessibility, validation, and disabled presentation remain authoritative.

The optional note field is always visible, including when empty. Its label is `Заметка · необязательно`, its placeholder is `Пара слов о событии`, and its counter starts at `0/280`. The label and counter use native caption and caption2 roles; the multiline native text field inherits the editor’s 13-point body text and displays two to three lines. There is no note disclosure action.

The `Значок` field is an outlined selection control with label, selected emoji or `Без значка`, disclosure chevron, and a separate clear target when selected. Clearing does not disclose the picker. Its inline picker uses eight compact presets followed by the larger catalog. Disclosure uses height and opacity over 200 ms; selected-value opacity takes 120 ms. Reduce Motion makes both immediate. The inline catalog uses the same paper surface and border language rather than a separate window.

### Navigation

The fixed list footer carries local-storage reassurance, a small settings gear, and Quit. The gear symbol is 14 points in a 22-point activation area. Settings has an explicit back control and a Georgia heading. Settings groups are functional labels with native controls; update and diagnostic rows are actions without navigation arrows. Inactive list content is removed from interaction and accessibility while the editor or settings is active.

### Calendar Leaves

A real month label sits in a terracotta strip above the Georgia day numeral, without a leading zero. The strip fills the top edge and rounded upper corners without an uncolored inset. Featured leaves measure 54 × 65 points; secondary leaves measure 42 × 51. The slight rotation and clean outline make this the signature material gesture, without a shadow. Optional event emoji belongs immediately before the event title; empty and legacy calendar emoji are omitted in the list because the leaf already carries the date.

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
