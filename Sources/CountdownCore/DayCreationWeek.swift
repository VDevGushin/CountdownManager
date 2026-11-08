import Foundation

/// A reviewed set of civil dates. Confirmation must still use the same reference day.
public struct DayCreationWeek: Equatable {
    public let referenceDay: Day
    public let days: [Day]
    public let isNextWeek: Bool

    public init?(today: Day, calendar: Calendar = Day.calendar) {
        let start = today.date(calendar: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let count = weekday == 1 ? 7 : 8 - weekday
        guard (1...7).contains(count) else { return nil }
        var dates: [Day] = []
        for offset in 1...count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = Day(date, calendar: calendar)
            guard (1...9999).contains(day.year), day > (dates.last ?? today) else { return nil }
            dates.append(day)
        }
        referenceDay = today
        days = dates
        isNextWeek = weekday == 1
    }
}

extension CountdownData {
    /// Any event occupying the full civil date prevents another week-generated day on that date.
    public func containsEvent(on day: Day) -> Bool {
        items.contains { $0.date == day }
    }

    /// Builds the complete candidate before replacing the snapshot using the same rule as the preview.
    public mutating func createMissingDays(in week: DayCreationWeek, today: Day) throws -> [Countdown] {
        guard week.referenceDay == today else { throw CountdownError.date }
        let missing = week.days.filter { !containsEvent(on: $0) }
        guard !missing.isEmpty else { return [] }
        var updated = self
        var created: [Countdown] = []
        for day in missing {
            let item = Countdown(title: automaticEventTitle(for: day), date: day, emoji: "",
                                 showsWeather: true, usesAutomaticTitle: true, isDay: true)
            try updated.save(item, primary: false, today: today)
            created.append(item)
        }
        self = updated
        return created
    }
}
