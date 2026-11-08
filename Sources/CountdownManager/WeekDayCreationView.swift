import CountdownCore
import SwiftUI

package func weekCreationTitle(for today: Day) -> String {
    DayCreationWeek(today: today)?.isNextWeek == true ? "На следующую неделю" : "До конца недели"
}

private struct WeekDayCreationRow: Identifiable {
    let day: Day
    let alreadyExists: Bool

    var id: String { String(format: "%04d-%02d-%02d", day.year, day.month, day.day) }
}

/// Presentation-local review state. Both surfaces reserve the existing shared editing session before entry.
struct WeekDayCreationView: View {
    @ObservedObject var store: Store
    let didCreate: ([Countdown]) -> Void
    let cancel: () -> Void
    @State private var week: DayCreationWeek
    @State private var isSaving = false
    @State private var notice: String?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    init(store: Store, week: DayCreationWeek, didCreate: @escaping ([Countdown]) -> Void,
         cancel: @escaping () -> Void) {
        self.store = store
        self.didCreate = didCreate
        self.cancel = cancel
        _week = State(initialValue: week)
    }

    private var rows: [WeekDayCreationRow] {
        week.days.map { day in
            WeekDayCreationRow(day: day, alreadyExists: store.data.containsEvent(on: day))
        }
    }
    private var missingCount: Int { rows.filter { !$0.alreadyExists }.count }
    private var canCreate: Bool {
        missingCount > 0 && !isSaving && !store.hasPendingPersistence && store.eventCreationIsAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(week.isNextWeek ? "На следующую неделю" : "До конца недели")
                .font(.custom("Georgia", size: 21)).tracking(-0.5)
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("creation.week.title")
                .uiSmokeControl(id: "creation.week.title",
                                value: { week.isNextWeek ? "На следующую неделю" : "До конца недели" })
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let first = week.days.first, let last = week.days.last {
                        Text(first == last ? humanDateLabel(first) : "\(humanDateLabel(first)) — \(humanDateLabel(last))")
                            .font(.system(size: 12))
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    }
                    if let notice {
                        Text(notice).font(.system(size: 12))
                            .foregroundStyle(AuroraInstrument.warningInk(for: colorScheme,
                                                                       highContrast: accessibilitySettings.prefersHighContrast))
                            .accessibilityIdentifier("creation.week.notice")
                            .uiSmokeControl(id: "creation.week.notice", value: { notice })
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            previewRow(row, index: index)
                            if index < rows.count - 1 { Divider() }
                        }
                    }
                    Text(missingCount == 0 ? "На всех датах уже есть события."
                         : "Даты с событиями будут пропущены. Остальные дни будут созданы.")
                        .font(.system(size: 11))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .uiSmokeControl(id: "creation.week.count", value: { String(missingCount) })
                }
                .padding(16)
            }
            .disabled(isSaving)
            Divider()
            HStack(spacing: 10) {
                if isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Отмена", action: cancelPreview)
                    .auroraSecondaryAction()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("creation.week.cancel")
                    .uiSmokeControl(id: "creation.week.cancel", action: cancelPreview)
                    .disabled(isSaving)
                Button(missingCount == 0 ? "Нет новых дней" : "Создать \(missingCount) \(dayCountNoun(missingCount))",
                       action: create)
                    .auroraPrimaryAction()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("creation.week.confirm")
                    .uiSmokeControl(id: "creation.week.confirm", action: create,
                                    value: { String(missingCount) })
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
        }
        .font(.system(size: 13))
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .background(AuroraPanelCanvas())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("creation.week.preview")
        .uiSmokeControl(id: "creation.week.preview")
    }

    private func previewRow(_ row: WeekDayCreationRow, index: Int) -> some View {
        HStack(spacing: 12) {
            PlannerCalendarDateTile(monthControlID: "creation.week.month.\(index)", day: row.day, isFeatured: false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(russianWeekdayTitle(row.day)).font(.system(size: 13, weight: .semibold))
                Text(humanDateLabel(row.day)).font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            Spacer(minLength: 4)
            Text(row.alreadyExists ? "Уже есть" : "Будет создан")
                .font(.system(size: 11))
                .foregroundStyle(row.alreadyExists ? AuroraInstrument.secondaryInk(for: colorScheme)
                                 : AuroraInstrument.accent(for: colorScheme,
                                                           highContrast: accessibilitySettings.prefersHighContrast))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("creation.week.row.\(index)")
        .uiSmokeControl(id: "creation.week.row.\(index)",
                        value: { "\(row.id)|\(row.alreadyExists ? "existing" : "new")" })
    }

    private func cancelPreview() {
        guard !isSaving else { return }
        cancel()
    }

    private func create() {
        guard canCreate else { return }
        isSaving = true
        Task {
            if let created = await store.createWeekDays(week) {
                didCreate(created)
                cancel()
            } else if week.referenceDay != store.today, let refreshed = DayCreationWeek(today: store.today) {
                week = refreshed
                notice = EventUIStrings.weekDateChanged
                if store.error == EventUIStrings.weekDateChanged { store.error = nil }
            }
            isSaving = false
        }
    }

    private func dayCountNoun(_ count: Int) -> String {
        count == 1 ? "день" : ((2...4).contains(count) ? "дня" : "дней")
    }
}
