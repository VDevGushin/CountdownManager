import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class CountdownTimer: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(remainingSeconds: Int)
        case finished
    }

    private static let deadlineKey = "timer.deadline"
    private static let notificationIdentifier = "countdown-manager.timer"

    @Published private(set) var deadline: Date?
    @Published private(set) var now: Date

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private var ticker: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        now = Date()
        if let storedDeadline = defaults.object(forKey: Self.deadlineKey) as? Double {
            deadline = Date(timeIntervalSince1970: storedDeadline)
        } else {
            deadline = nil
        }

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] currentDate in
                guard let self, let deadline = self.deadline else { return }
                if currentDate < deadline || self.now < deadline {
                    self.now = currentDate
                }
            }
    }

    var phase: Phase {
        guard let deadline else { return .idle }
        let interval = deadline.timeIntervalSince(now)
        guard interval > 0 else { return .finished }
        let bounded = min(ceil(interval), Double(Int.max))
        return .running(remainingSeconds: Int(bounded))
    }

    var statusTitle: String? {
        switch phase {
        case .idle:
            return nil
        case let .running(remainingSeconds):
            return "⏰ \(countdownTimerLabel(remainingSeconds))"
        case .finished:
            return "⏰"
        }
    }

    var statusToolTip: String? {
        switch phase {
        case .idle:
            return nil
        case let .running(remainingSeconds):
            return "Таймер: \(countdownTimerLabel(remainingSeconds))"
        case .finished:
            return "Время вышло"
        }
    }

    func start(minutes: Int) {
        guard minutes > 0, minutes <= Int.max / 60 else { return }
        let startedAt = Date()
        let newDeadline = startedAt.addingTimeInterval(TimeInterval(minutes) * 60)
        now = startedAt
        deadline = newDeadline
        defaults.set(newDeadline.timeIntervalSince1970, forKey: Self.deadlineKey)
        scheduleNotification(for: newDeadline)
        DiagnosticLog.shared.record("timer.start minutes=\(minutes)")
    }

    func delete() {
        deadline = nil
        now = Date()
        defaults.removeObject(forKey: Self.deadlineKey)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        DiagnosticLog.shared.record("timer.delete")
    }

    private func scheduleNotification(for deadline: Date) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])

        Task { [weak self] in
            guard let self else { return }
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
                guard granted, self.deadline == deadline else { return }
                let interval = deadline.timeIntervalSinceNow
                guard interval > 0 else { return }

                let content = UNMutableNotificationContent()
                content.title = "⏰ Время вышло"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, interval),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: Self.notificationIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await notificationCenter.add(request)
                DiagnosticLog.shared.record("timer.notification scheduled")
            } catch {
                DiagnosticLog.shared.record("timer.notification failure error=\(error.localizedDescription)")
            }
        }
    }
}

func countdownTimerLabel(_ totalSeconds: Int) -> String {
    let seconds = max(0, totalSeconds)
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remainder = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
}

struct CountdownManagerRootView: View {
    @ObservedObject var timer: CountdownTimer
    let store: Store

    var body: some View {
        VStack(spacing: 0) {
            CountdownTimerStrip(timer: timer)
            Divider()
            ManagerView(store: store)
        }
        .frame(width: 390, height: 600)
    }
}

private struct CountdownTimerStrip: View {
    @ObservedObject var timer: CountdownTimer
    @State private var selectedMinutes = 30
    @State private var customMinutes = ""

    private var resolvedMinutes: Int? {
        if selectedMinutes > 0 { return selectedMinutes }
        guard let value = Int(customMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0,
              value <= Int.max / 60 else { return nil }
        return value
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("⏰")
                .font(.system(size: 20))
                .accessibilityHidden(true)

            switch timer.phase {
            case .idle:
                idleControls
            case let .running(remainingSeconds):
                Text(countdownTimerLabel(remainingSeconds))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("timer.running")
                Spacer()
                deleteButton
            case .finished:
                Text("Время вышло")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("timer.finished")
                Spacer()
                deleteButton
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 59)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer")
    }

    private var idleControls: some View {
        HStack(spacing: 8) {
            Picker("Время таймера", selection: $selectedMinutes) {
                Text("15").tag(15)
                Text("30").tag(30)
                Text("60").tag(60)
                Text("Своё").tag(0)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 205)
            .accessibilityIdentifier("timer.duration")

            if selectedMinutes == 0 {
                TextField("мин", text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .accessibilityLabel("Минуты")
                    .accessibilityIdentifier("timer.custom")
            } else {
                Spacer(minLength: 0)
            }

            Button {
                guard let minutes = resolvedMinutes else { return }
                timer.start(minutes: minutes)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Запустить")
            .accessibilityLabel("Запустить таймер")
            .accessibilityIdentifier("timer.start")
            .disabled(resolvedMinutes == nil)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            timer.delete()
        } label: {
            Image(systemName: "trash")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Удалить таймер")
        .accessibilityLabel("Удалить таймер")
        .accessibilityIdentifier("timer.delete")
    }
}
