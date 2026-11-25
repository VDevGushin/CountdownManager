# Material search captures

Both README images came from one local build of `codex/desktop-material-search` on macOS 27.2.1
using `build.sh` with updates disabled. The executable version is 1.25.3/50, built with SDK 27.2
and linked compatibility 13.0. Executable SHA-256 is
`fa1399a6185266e48d562f38868a149138c73338ff9909cd930376f52ef573d4`.

- [Desktop filename search](material-search-file-dark.png) is a 2400 × 1616 native render from
  `--ui-smoke-desktop --ui-smoke-subtask-search`, which passed 3/3 scenarios. SHA-256 is
  `3b7486d062b6966ca09a7d0ca95a37a794476fbd0f4d4c7c51f854cf881b12be`.
- [Light mini-panel](identity-panel-favorite-light.png) is a 780 × 1200 native render from
  `--ui-smoke-menu-identity-captures`, which passed 4/4 scenarios. SHA-256 is
  `fc8710ef86042fd2674d20942ab8e477f4586b83f0950c6557d92b98720cf905`.

The two captures were inspected visually. The dark and light renders of filename and address
matches were compared with the existing task snippet. Both runs used isolated synthetic data.

## Extended manual acceptance on macOS 27.2.1

The run used native keyboard and pointer input on the build that preceded the code review below.
The retest used a temporary app with a distinct
bundle identifier for unambiguous input routing. The executable bytes after stripping the two
copies' signatures matched at SHA-256 `23248ea8053ee40a4e68d91d00b5db08284b58eeb50342464629ecf714f58ed1`.

| Scenario | Observation |
| --- | --- |
| Embedded LF and CRLF in attachment filenames | The original card hid the match after the break. The retest showed the filename on one line with the matching text highlighted. |
| Long address in a narrow grid card, then a wide feed row | The original grid cut off the end of `PLATFORM-MAP`. The retest showed the whole match. The wide feed row retained surrounding context. |
| Names, addresses and Unicode | Filenames, link names, host and path matched. Mixed case, outer whitespace, NFC/NFD and a compound emoji worked. A percent-encoded address was searchable as stored. |
| Multiple matches and navigation | One card per event, 18 simultaneous results, active-task precedence, and completed-task strikethrough. Retained past events matched. Clearing results restored 24 available cards and removed match labels. Switching between grid and feed and returning from the panel preserved selection and query. |
| Keyboard and accessibility | Rapid input and correction preserved field focus. Card accessibility labels included the type and matched text. VoiceOver speech was outside this run. |
| Editor and storage | A fresh import was searchable after Save. Cancelling an edit preserved the query, link and attachment. A saved link edit replaced the old searchable address. After read-only retest actions, all 19 isolated JSON, owned file and marker hashes matched. |

Strict SwiftLint, `./verify.sh fast`, and both native capture runs passed after the two fixes.
A separate release-mode model probe searched 5,000 synthetic events with 25 materials each.
It returned the expected result counts with a median of about 450 ms for a no-match query.
The model probe did not measure window input or rendering at that scale.

## Follow-up code review

Highlight ranges now come from the saved string before line breaks are replaced for display.
The regression reproduces the previous duplicate highlight for a name containing both `A B` and
`A` followed by a line break and `B`. A separate probe passed 3,993 combinations of Unicode text,
queries and line separators without altering the displayed UTF-8 beyond the intended replacements.
The root now uses one filtered collection per render for browsing and selection. Shared event
labels come from `EventUIStrings`.

Strict SwiftLint and `./verify.sh fast` passed. On the executable above, the native search run
passed 3/3, mini-panel capture 4/4, and attachment shelf and Quick Look run 7/7.
The two fresh README captures were byte-identical to the previously inspected images.
