import AppKit
import Combine
import Foundation
import SwiftUI

package let countdownTimerPresetMinutes = [5, 10, 15, 30, 40, 60, 120]
package let countdownTimerMaximumMinutes = 120

package enum TimerPresetSelectionMotion: Equatable {
    case immediate
    case slide(duration: TimeInterval)
}

package func timerPresetSelectionMotion(reduceMotion: Bool) -> TimerPresetSelectionMotion {
    reduceMotion ? .immediate : .slide(duration: 0.18)
}

package func validatedTimerDeadline(timeIntervalSince1970: Double, now: Date) -> Date? {
    let deadline = Date(timeIntervalSince1970: timeIntervalSince1970)
    let remaining = deadline.timeIntervalSince(now)
    guard remaining.isFinite,
          remaining <= TimeInterval(countdownTimerMaximumMinutes * 60) else { return nil }
    return deadline
}

package func timerCrossedDeadline(previousNow: Date, currentNow: Date, deadline: Date) -> Bool {
    previousNow < deadline && currentNow >= deadline
}

@MainActor
final class CountdownTimer: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(remainingSeconds: Int)
        case finished
    }

    static let deadlineKey = "timer.deadline"
    @Published private(set) var deadline: Date?
    @Published private(set) var now: Date

    private let defaults: UserDefaults
    private var ticker: AnyCancellable?
    private let completionSubject = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        now = Date()
        let storedValue = defaults.object(forKey: Self.deadlineKey)
        let storedDeadline = (storedValue as? Double).flatMap {
            validatedTimerDeadline(timeIntervalSince1970: $0, now: now)
        }
        deadline = storedDeadline
        let discardedInvalidDeadline = storedValue != nil && storedDeadline == nil

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] currentDate in
                self?.refresh(at: currentDate)
            }

        if discardedInvalidDeadline {
            defaults.removeObject(forKey: Self.deadlineKey)
            DiagnosticLog.shared.record("timer.invalid-deadline-cleared")
        }
    }

    var completionPublisher: AnyPublisher<Void, Never> {
        completionSubject.eraseToAnyPublisher()
    }

    var phase: Phase {
        guard let deadline else { return .idle }
        let interval = deadline.timeIntervalSince(now)
        guard interval > 0 else { return .finished }
        let bounded = min(ceil(interval), Double(countdownTimerMaximumMinutes * 60))
        return .running(remainingSeconds: Int(bounded))
    }

    var statusTitle: String? {
        switch phase {
        case .idle:
            return nil
        case let .running(remainingSeconds):
            return countdownTimerLabel(remainingSeconds)
        case .finished:
            return ""
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
        guard countdownTimerPresetMinutes.contains(minutes) else { return }
        let startedAt = Date()
        let newDeadline = startedAt.addingTimeInterval(TimeInterval(minutes) * 60)
        now = startedAt
        deadline = newDeadline
        defaults.set(newDeadline.timeIntervalSince1970, forKey: Self.deadlineKey)
        DiagnosticLog.shared.record("timer.start minutes=\(minutes)")
    }

    func delete() {
        deadline = nil
        now = Date()
        defaults.removeObject(forKey: Self.deadlineKey)
        DiagnosticLog.shared.record("timer.delete")
    }

    private func refresh(at currentDate: Date) {
        guard let deadline else { return }
        let previousNow = now
        if currentDate < deadline || previousNow < deadline {
            now = currentDate
        }
        if timerCrossedDeadline(previousNow: previousNow, currentNow: currentDate, deadline: deadline) {
            DiagnosticLog.shared.record("timer.finished")
            completionSubject.send()
        }
    }
}

package func countdownTimerLabel(_ totalSeconds: Int) -> String {
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
    @ObservedObject var accessibilitySettings: AuroraAccessibilitySettings
    @ObservedObject var visualEnvironment: UISmokeVisualEnvironment
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        VStack(spacing: 0) {
            CountdownTimerStrip(timer: timer)
            ManagerView(store: store)
        }
        .frame(width: 390, height: 600)
        .background(AuroraPanelCanvas())
        .environmentObject(accessibilitySettings)
        .environment(\.colorScheme, visualEnvironment.colorSchemeOverride ?? systemColorScheme)
    }
}

private struct CountdownTimerStrip: View {
    @ObservedObject var timer: CountdownTimer
    @State private var selectedMinutes = 30
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            timerIcon

            switch timer.phase {
            case .idle:
                idleControls
            case let .running(remainingSeconds):
                Text(countdownTimerLabel(remainingSeconds))
                    .font(.system(size: 23, weight: .semibold))
                    .monospacedDigit()
                    .animation(
                        accessibilitySettings.prefersReducedMotion ? nil : .easeOut(duration: 0.1),
                        value: remainingSeconds
                    )
                    .accessibilityIdentifier("timer.running")
                Spacer()
                deleteButton
            case .finished:
                Text("Время вышло")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        AuroraInstrument.finishedColor(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        )
                    )
                    .accessibilityIdentifier("timer.finished")
                Spacer()
                deleteButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 59)
        .background(AuroraTimerBackground(appearance: auroraAppearance))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer")
        .uiSmokeControl(id: "timer")
    }

    private var auroraAppearance: AuroraTimerAppearance {
        switch timer.phase {
        case .idle:
            .idle
        case .running:
            .running
        case .finished:
            .finished
        }
    }

    @ViewBuilder
    private var timerIcon: some View {
        if timer.phase == .idle {
            Image(systemName: "clock")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .frame(width: 20)
                .accessibilityHidden(true)
        } else {
            Text("⏰")
                .font(.system(size: 20))
                .frame(width: 20)
                .accessibilityHidden(true)
        }
    }

    private var idleControls: some View {
        HStack(spacing: 8) {
            AuroraTimerPresetSelector(
                presets: countdownTimerPresetMinutes,
                selection: $selectedMinutes
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("timer.duration")
            .uiSmokeControl(id: "timer.duration", value: { String(selectedMinutes) })

            Button {
                timer.start(minutes: selectedMinutes)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color(red: 0.18, green: 0.14, blue: 0.11) : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AuroraInstrument.accent(
                                for: colorScheme,
                                highContrast: accessibilitySettings.prefersHighContrast
                            ))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Запустить")
            .accessibilityLabel("Запустить таймер")
            .accessibilityIdentifier("timer.start")
            .uiSmokeControl(id: "timer.start", action: { timer.start(minutes: selectedMinutes) })
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            timer.delete()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Удалить таймер")
        .accessibilityLabel("Удалить таймер")
        .accessibilityIdentifier("timer.delete")
    }
}
