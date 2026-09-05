import Foundation
import CountdownCore
import CountdownManagerUI

@main
enum UIChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountdownManagerUIChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let today = Day(Date())
        let yesterdayDate = Day.calendar.date(byAdding: .day, value: -1, to: today.date())!
        let tomorrowDate = Day.calendar.date(byAdding: .day, value: 1, to: today.date())!
        let expiredItem = Countdown(title: "Expired UI", date: Day(yesterdayDate), emoji: "⌛️")
        let todayItem = Countdown(title: "Today UI", note: "Visible note", date: today, emoji: "☀️")
        let futureItem = Countdown(title: "Future UI", note: "Editable note", date: Day(tomorrowDate), emoji: "🚀")
        var data = CountdownData()
        data.items = [expiredItem, todayItem, futureItem]
        data.primaryID = futureItem.id

        precondition(activeCountdowns(in: data, today: today).map(\.id) == [futureItem.id, todayItem.id])
        let todayRow = CountdownRowPresentation(item: todayItem, today: today, primaryID: data.primaryID)
        precondition(todayRow.note == "Visible note")
        precondition(todayRow.remainingLabel == "Сегодня")
        precondition(todayRow.isToday)
        precondition(!todayRow.isPrimary)

        precondition(editorCanSave(
            title: "Future UI",
            note: String(repeating: "я", count: 280),
            date: futureItem.date,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "Future UI",
            note: String(repeating: "я", count: 281),
            date: futureItem.date,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "   ",
            note: "",
            date: futureItem.date,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "Today is invalid for creation",
            note: "",
            date: today,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "Invalid emoji",
            note: "",
            date: futureItem.date,
            emoji: "abc",
            today: today
        ))

        data.primaryID = todayItem.id
        precondition(activeCountdowns(in: data, today: today).map(\.id) == [todayItem.id, futureItem.id])
        let selectedRow = CountdownRowPresentation(item: todayItem, today: today, primaryID: data.primaryID)
        precondition(selectedRow.isPrimary)

        let fileURL = directory.appendingPathComponent("countdowns.json")
        let repository = CountdownRepository(fileURL: fileURL)
        let didSave = try await repository.save(data, revision: 1)
        let loaded = try await repository.load()
        precondition(didSave)
        precondition(loaded.primaryID == todayItem.id)

        print("PASS UI state: active filtering, note and Today presentation, complete editor validation, primary reordering and persistence")
    }
}
