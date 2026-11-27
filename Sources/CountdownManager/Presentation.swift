import Foundation
import CountdownCore

/// A show request is not a presented panel until WindowServer reports visible occlusion state.
package struct PanelPresentationState: Equatable {
    package enum StatusAction: String {
        case show, hide
        case alreadyHidden = "already-hidden"
    }

    package struct StatusPress: Equatable {
        let session: UInt32
        let hardware: UInt32
        let keyboard: UInt32

        package init(session: UInt32, hardware: UInt32, keyboard: UInt32 = 0) {
            self.session = session
            self.hardware = hardware
            self.keyboard = keyboard
        }
    }

    package private(set) var requestedVisible = false
    package private(set) var hasVisibleAcknowledgement = false
    private var lastHandledStatusPress: StatusPress?
    private var statusPressThatDismissedPanel: StatusPress?

    package init() {}

    package func hasShowRequestHere(isOnActiveSpace: Bool) -> Bool {
        // Before the window server acknowledges a show, its Space can still reflect the last presentation.
        requestedVisible && (!hasVisibleAcknowledgement || isOnActiveSpace)
    }

    package mutating func statusAction(press: StatusPress?, isOnActiveSpace: Bool) -> StatusAction {
        let alreadyHidden = matchesDismissingPress(press)
        statusPressThatDismissedPanel = nil
        if let press { lastHandledStatusPress = press }
        if alreadyHidden { return .alreadyHidden }
        return hasShowRequestHere(isOnActiveSpace: isOnActiveSpace) ? .hide : .show
    }

    private func matchesDismissingPress(_ press: StatusPress?) -> Bool {
        guard let press, let dismissed = statusPressThatDismissedPanel,
              press.keyboard == dismissed.keyboard else { return false }
        if press == dismissed { return true }
        // Forwarding a hardware press to the status button can also advance the session counter.
        return press.hardware != 0 && press.hardware == dismissed.hardware
            && press.hardware != lastHandledStatusPress?.hardware
    }

    package mutating func recordStatusPressDuringDeactivation(
        _ press: StatusPress, buttonIsDown: Bool, usesNativeSession: Bool = false
    ) -> Bool {
        let hasNewMouseDown = press.session != lastHandledStatusPress?.session
            || press.hardware != lastHandledStatusPress?.hardware
        // A focus switch with the pointer parked on the item can see counters from a prior press.
        guard requestedVisible, buttonIsDown, usesNativeSession || hasNewMouseDown else { return false }
        statusPressThatDismissedPanel = press
        return true
    }

    package mutating func clearStatusPressDuringDeactivation() {
        statusPressThatDismissedPanel = nil
    }

    package mutating func requestShow() {
        clearStatusPressDuringDeactivation()
        requestedVisible = true
        hasVisibleAcknowledgement = false
    }

    package mutating func requestHide() {
        requestedVisible = false
        hasVisibleAcknowledgement = false
    }

    /// Returns whether an acknowledged presentation has become occluded and must be hidden.
    package mutating func observeOcclusion(isVisible: Bool) -> Bool {
        guard requestedVisible else { return false }
        if isVisible {
            hasVisibleAcknowledgement = true
            return false
        }
        return hasVisibleAcknowledgement
    }
}

package enum EventUIStrings {
    package static var addEvent: String { AppText.string("event.add") }
    package static var newEvent: String { AppText.string("event.new") }
    package static var editEvent: String { AppText.string("event.edit") }
    package static var createDay: String { AppText.string("event.createDay") }
    package static var newDay: String { AppText.string("event.newDay") }
    package static var weekDateChanged: String { AppText.string("event.weekDateChanged") }
    package static var todayExpiryNotice: String { AppText.string("event.todayExpiryNotice") }
    package static var deleteEvent: String { AppText.string("event.deletePrompt") }
    package static var emptyTitle: String { AppText.string("event.emptyTitle") }
    package static var emptyMessage: String { AppText.string("event.emptyMessage") }
}

package enum EventEmojiCatalog {
    package static let presets = ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️"]
}

package enum EditorLayout {
    /// Space reserved between focusable controls and the clipping ScrollView viewport.
    package static let focusRingInset: CGFloat = 4
    /// Keeps editor controls clear of the overlay scroll indicator.
    package static let scrollIndicatorClearance: CGFloat = 10
    /// Separates the scrolling form from persistent editor actions.
    package static let actionAreaSpacing: CGFloat = 16
}

package enum SubtaskDisclosureMotion: Equatable {
    case immediate
    case heightAndOpacity(duration: TimeInterval)
}

package func subtaskDisclosureMotion(reduceMotion: Bool) -> SubtaskDisclosureMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.2)
}

package func editorSubtaskMotion(reduceMotion: Bool) -> SubtaskDisclosureMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.1)
}

package enum EditorEmojiPickerState: Equatable {
    case closed
    case presets
    case catalog(page: Int)

    package var isOpen: Bool { self != .closed }
    package var isCatalog: Bool {
        if case .catalog = self { return true }
        return false
    }
    package var pageIndex: Int {
        if case let .catalog(page) = self { return page }
        return 0
    }

    package mutating func toggle() {
        self = isOpen ? .closed : .presets
    }

    package mutating func showCatalog() {
        guard self == .presets else { return }
        self = .catalog(page: 0)
    }

    package mutating func setPage(_ page: Int, pageCount: Int) {
        guard isCatalog, pageCount > 0 else { return }
        self = .catalog(page: min(max(page, 0), pageCount - 1))
    }

    package mutating func close() {
        self = .closed
    }
}

package enum EditorEmojiPickerMotion: Equatable {
    case immediate
    case heightAndOpacity(duration: TimeInterval)
}

package func editorEmojiPickerMotion(reduceMotion: Bool) -> EditorEmojiPickerMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.2)
}

package let editorEmojiValueTransitionDuration: TimeInterval = 0.12

func checklistDisplayOrder(_ subtasks: [Subtask]) -> [Subtask] {
    subtasks.filter { !$0.isCompleted } + subtasks.filter(\.isCompleted)
}

package struct CountdownRowPresentation: Equatable {
    package let note: String?
    package let dateLabel: String
    package let remainingLabel: String
    package let remainingDays: Int
    package let dateAndRemainingLabel: String
    package let isToday: Bool
    package let isPast: Bool
    package let isPrimary: Bool
    package var isFeatured: Bool { isPrimary }
    package let activeSubtasks: [Subtask]
    package let completedSubtasks: [Subtask]
    package let completionLabel: String?
    package var allSubtasksCompleted: Bool { !completedSubtasks.isEmpty && activeSubtasks.isEmpty }

    package init(item: Countdown, today: Day, primaryID: UUID?) {
        remainingDays = item.date.days(from: today)
        note = item.note
        dateLabel = humanDateLabel(item.date)
        remainingLabel = relativeCountdownLabel(remainingDays)
        dateAndRemainingLabel = "\(dateLabel) · \(remainingLabel)"
        isToday = remainingDays == 0
        isPast = remainingDays < 0
        isPrimary = primaryID == item.id
        activeSubtasks = item.subtasks.filter { !$0.isCompleted }
        completedSubtasks = item.subtasks.filter(\.isCompleted)
        completionLabel = item.subtasks.isEmpty
            ? nil
            : "\(completedSubtasks.count)/\(item.subtasks.count)"
    }
}

package func relativeCountdownLabel(_ days: Int) -> String {
    switch days {
    case ..<(-1): return AppText.string("calendar.pastCountdown", dayLabel(-days))
    case -1: return AppText.string("calendar.yesterday")
    case 0: return AppText.string("calendar.today")
    case 1: return AppText.string("calendar.tomorrow")
    default: return AppText.string("calendar.futureCountdown", dayLabel(days))
    }
}

package struct CalendarDateTilePresentation: Equatable {
    package let monthLabel: String
    package let dayLabel: String

    private static var shortMonths: [String] { [
        AppText.string("calendar.month.abbreviated.january"), AppText.string("calendar.month.abbreviated.february"),
        AppText.string("calendar.month.abbreviated.march"), AppText.string("calendar.month.abbreviated.april"),
        AppText.string("calendar.month.abbreviated.may"), AppText.string("calendar.month.abbreviated.june"),
        AppText.string("calendar.month.abbreviated.july"), AppText.string("calendar.month.abbreviated.august"),
        AppText.string("calendar.month.abbreviated.september"), AppText.string("calendar.month.abbreviated.october"),
        AppText.string("calendar.month.abbreviated.november"), AppText.string("calendar.month.abbreviated.december")
    ] }

    package init(day: Day) {
        monthLabel = Self.shortMonths[day.month - 1]
        dayLabel = String(day.day)
    }
}

package func eventListEmoji(_ emoji: String) -> String? {
    emoji.isEmpty || emoji == "📅" ? nil : emoji
}

private var genitiveMonths: [String] { [
    AppText.string("calendar.month.genitive.january"), AppText.string("calendar.month.genitive.february"),
    AppText.string("calendar.month.genitive.march"), AppText.string("calendar.month.genitive.april"),
    AppText.string("calendar.month.genitive.may"), AppText.string("calendar.month.genitive.june"),
    AppText.string("calendar.month.genitive.july"), AppText.string("calendar.month.genitive.august"),
    AppText.string("calendar.month.genitive.september"), AppText.string("calendar.month.genitive.october"),
    AppText.string("calendar.month.genitive.november"), AppText.string("calendar.month.genitive.december")
] }

package func humanDateLabel(_ day: Day, includesYear: Bool = true) -> String {
    let dayNumber = String(day.day)
    let months = genitiveMonths
    guard months.indices.contains(day.month - 1) else {
        let dayAndMonth = "\(day.day).\(day.month)"
        return includesYear ? "\(dayAndMonth).\(day.year)" : dayAndMonth
    }
    let month = months[day.month - 1]
    if includesYear { return AppText.string("calendar.fullDate", dayNumber, month, String(day.year)) }
    return AppText.string("calendar.shortDate", dayNumber, month)
}

package func subtaskDisclosureLabel(isExpanded: Bool, completion: String) -> String {
    "\(isExpanded ? "▾" : "▸") \(completion)"
}

package enum StatusBarIcon: String, Equatable {
    case mars = "MarsMenu"
    case calendar = "CalendarMenu"
}

package struct StatusBarPresentation: Equatable {
    package let title: String
    package let icon: StatusBarIcon?
    package let toolTip: String

    package init(title: String, icon: StatusBarIcon?, toolTip: String) {
        self.title = title
        self.icon = icon
        self.toolTip = toolTip
    }
}

package func statusBarPresentation(data: CountdownData, today: Day) -> StatusBarPresentation {
    guard let favorite = data.items.first(where: { $0.id == data.primaryID && $0.isAvailable(on: today) }) else {
        let hasEvents = data.items.contains { $0.isAvailable(on: today) }
        return StatusBarPresentation(
            title: "",
            icon: .mars,
            toolTip: hasEvents ? AppText.string("app.status.noFavorite") : AppText.string("app.status.noEvents")
        )
    }
    let days = favorite.date.days(from: today)
    let remaining = days < 0 ? relativeCountdownLabel(days) : (days == 1 ? AppText.string("calendar.tomorrow") : countdownLabel(days))
    if eventListEmoji(favorite.emoji) == nil {
        return StatusBarPresentation(title: remaining, icon: .calendar, toolTip: "Countdown Manager · \(remaining)")
    }
    let title = "\(favorite.emoji) \(remaining)"
    return StatusBarPresentation(title: title, icon: nil, toolTip: title)
}

package func statusBarTitle(data: CountdownData, today: Day) -> String {
    statusBarPresentation(data: data, today: today).title
}

package func activeCountdowns(in data: CountdownData, today: Day) -> [Countdown] {
    data.items.enumerated()
        .filter { $0.element.isAvailable(on: today) }
        .sorted {
            let lhsPrimary = $0.element.id == data.primaryID
            let rhsPrimary = $1.element.id == data.primaryID
            if lhsPrimary != rhsPrimary { return lhsPrimary }
            let lhsPast = $0.element.date < today
            let rhsPast = $1.element.date < today
            if lhsPast != rhsPast { return !lhsPast }
            if $0.element.date != $1.element.date {
                return lhsPast ? $0.element.date > $1.element.date : $0.element.date < $1.element.date
            }
            return $0.offset < $1.offset
        }
        .map(\.element)
}

package func editorCanSave(
    title: String,
    note: String,
    date: Day,
    emoji: String,
    subtasks: [Subtask] = [],
    links: [EventLink] = [],
    today: Day,
    savedNote: String? = nil,
    savedDate: Day? = nil
) -> Bool {
    let cleanedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    return (date >= today || date == savedDate)
        && (cleanedEmoji.isEmpty || CountdownData.isEmoji(cleanedEmoji))
        && editorContentCanSave(title: title, note: note, subtasks: subtasks, links: links, savedNote: savedNote)
}

func editorContentCanSave(
    title: String, note: String, subtasks: [Subtask], links: [EventLink], savedNote: String? = nil
) -> Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && CountdownNote.isAllowed(note, savedNote: savedNote)
        && subtasks.count <= Subtask.maximumCount
        && subtasks.allSatisfy {
            let cleaned = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleaned.isEmpty && cleaned.count <= Subtask.maximumTextLength
        }
        && (try? EventLink.validate(links)) != nil
}

package enum EditorFocusTarget: Hashable {
    case date
    case title
    case note
    case emoji
    case subtask(UUID)
}

package struct DayCreationPreset: Equatable {
    package let day: Day

    package init(day: Day) {
        self.day = day
    }

    package static func today(_ today: Day) -> DayCreationPreset {
        DayCreationPreset(day: today)
    }

    package static func tomorrow(after today: Day, calendar: Calendar = Day.calendar) -> DayCreationPreset? {
        guard let date = calendar.date(byAdding: .day, value: 1, to: today.date(calendar: calendar)) else {
            return nil
        }
        return DayCreationPreset(day: Day(date, calendar: calendar))
    }
}

package func eventCountLabel(_ count: Int) -> String {
    let noun: String
    switch AppText.pluralCategory(count) {
    case .one: noun = AppText.string("event.count.one")
    case .few: noun = AppText.string("event.count.few")
    case .many: noun = AppText.string("event.count.many")
    }
    return AppText.string("event.count.label", String(count), noun)
}

package func currentDayHeaderLabel(_ day: Day, locale: Locale = AppText.language.locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Day.calendar
    formatter.timeZone = Day.calendar.timeZone
    formatter.dateFormat = locale.language.languageCode?.identifier == "ru" ? "EEE, d MMMM" : "EEE, MMMM d"
    let label = formatter.string(from: day.date())
    return label.prefix(1).uppercased() + label.dropFirst()
}

package func applicationVersionLabel(bundle: Bundle = .main) -> String? {
    guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return AppText.string("app.version", version)
}

package struct EventEditorDraft: Equatable {
    package var title: String
    package var note: String
    package var emoji: String
    package var subtasks: [Subtask]
    package var links: [EventLink]
    package var attachments: [EventAttachment]
    package var showsWeather: Bool
    package var keepsAfterDate: Bool
    package private(set) var usesAutomaticTitle: Bool
    package private(set) var isDay: Bool

    package init(item: Countdown?) {
        title = item?.displayTitle ?? ""
        note = item?.note ?? ""
        emoji = item?.emoji ?? ""
        subtasks = item?.subtasks ?? []
        links = item?.links ?? []
        attachments = item?.attachments ?? []
        showsWeather = item?.showsWeather ?? false
        keepsAfterDate = item?.keepsAfterDate ?? false
        usesAutomaticTitle = item?.usesAutomaticTitle ?? false
        isDay = item?.isDay ?? false
    }

    init(record: UndatedRecord?) {
        self.init(item: nil)
        title = record?.title ?? ""
        note = record?.note ?? ""
        subtasks = record?.subtasks ?? []
        links = record?.links ?? []
        attachments = record?.attachments ?? []
    }

    package init(copying source: Countdown, date: Day) {
        self.init(item: source)
        subtasks = source.subtasks.map(Subtask.init(copying:))
        links = source.links.map { EventLink(name: $0.name, address: $0.address) }
        updateDayTitle(for: date)
    }

    package init(day: Day) {
        title = automaticEventTitle(for: day)
        note = ""
        emoji = ""
        subtasks = []
        attachments = []
        links = []
        showsWeather = true
        keepsAfterDate = false
        usesAutomaticTitle = true
        isDay = true
    }

    package mutating func setTitle(_ title: String) {
        guard title != self.title else { return }
        self.title = title
        usesAutomaticTitle = false
    }

    package mutating func updateDayTitle(for day: Day) {
        guard usesAutomaticTitle else { return }
        title = automaticEventTitle(for: day)
    }

    package mutating func useAutomaticTitle(for day: Day) {
        usesAutomaticTitle = true
        title = automaticEventTitle(for: day)
    }

    @discardableResult
    package mutating func addSubtask() -> EditorFocusTarget? {
        guard subtasks.count < Subtask.maximumCount,
              var subtask = try? Subtask(text: AppText.string("subtask.new")) else { return nil }
        subtask.text = ""
        subtasks.append(subtask)
        return .subtask(subtask.id)
    }

    @discardableResult
    package mutating func replaceEmoji(with symbol: String) -> Bool {
        guard CountdownData.isEmoji(symbol) else { return false }
        emoji = symbol
        return true
    }

    package mutating func clearEmoji() {
        emoji = ""
    }

    package func countdown(id: UUID, date: Day) -> Countdown {
        Countdown(
            id: id,
            title: title,
            note: note,
            date: date,
            emoji: emoji,
            subtasks: subtasks,
            showsWeather: showsWeather,
            keepsAfterDate: keepsAfterDate,
            usesAutomaticTitle: usesAutomaticTitle,
            isDay: isDay,
            attachments: attachments,
            links: links
        )
    }
}

package struct SubtaskDisclosurePersistence {
    private let defaults: UserDefaults
    private let key: String

    package init(defaults: UserDefaults = .standard, key: String = "expandedSubtasksByEvent") {
        self.defaults = defaults
        self.key = key
    }

    package func isExpanded(eventID: UUID) -> Bool {
        let values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        return values[eventID.uuidString] ?? true
    }

    package func setExpanded(_ isExpanded: Bool, eventID: UUID) {
        var values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        values[eventID.uuidString] = isExpanded
        defaults.set(values, forKey: key)
    }

    package func remove(eventID: UUID) {
        var values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        values.removeValue(forKey: eventID.uuidString)
        defaults.set(values, forKey: key)
    }
}
