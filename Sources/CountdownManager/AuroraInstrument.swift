import AppKit
import SwiftUI

final class AuroraAccessibilitySettings: ObservableObject {
    @Published private(set) var prefersHighContrast: Bool
    @Published private(set) var prefersReducedMotion: Bool

    private var displayOptionsObserver: NSObjectProtocol?
    private var isolatedCaptureOverride: Bool?
    private var isolatedReduceMotionOverride: Bool?

    init() {
        prefersHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        prefersReducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            prefersHighContrast = isolatedCaptureOverride
                ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            prefersReducedMotion = isolatedReduceMotionOverride
                ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    var isolatedCaptureOverrideValue: Bool? { isolatedCaptureOverride }
    var isolatedReduceMotionOverrideValue: Bool? { isolatedReduceMotionOverride }

    func setIsolatedCaptureOverrides(highContrast: Bool?, reduceMotion: Bool?) {
        // Smoke and capture modes validate their isolated test home before constructing this UI.
        guard UISmokeConfiguration.wasRequested else { return }
        isolatedCaptureOverride = highContrast
        isolatedReduceMotionOverride = reduceMotion
        prefersHighContrast = highContrast ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        prefersReducedMotion = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

enum AuroraInstrument {
    static let cardCornerRadius: CGFloat = 8
    static let controlCornerRadius: CGFloat = 8
    static let inputCornerRadius: CGFloat = 4
    static let emojiCornerRadius: CGFloat = 5

    static func accent(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if scheme == .dark {
            return highContrast ? Color(red: 1, green: 0.75, blue: 0.63) : Color(red: 0.96, green: 0.61, blue: 0.5)
        }
        return highContrast ? Color(red: 0.63, green: 0.17, blue: 0.1) : Color(red: 0.82, green: 0.28, blue: 0.18)
    }

    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.9, blue: 0.83) : Color(red: 0.19, green: 0.15, blue: 0.13)
    }

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.13, green: 0.11, blue: 0.1) : Color(red: 0.98, green: 0.96, blue: 0.93)
    }

    static func surface(for scheme: ColorScheme, elevated: Bool, highContrast: Bool) -> Color {
        if scheme == .dark {
            return elevated ? Color(red: 0.2, green: 0.16, blue: 0.13) : Color(red: 0.16, green: 0.13, blue: 0.11)
        }
        return highContrast ? .white : Color(red: 1, green: 0.98, blue: 0.95)
    }

    static func timerSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.18, green: 0.15, blue: 0.12) : Color(red: 0.95, green: 0.92, blue: 0.87)
    }

    static func stroke(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if highContrast {
            return scheme == .dark ? Color(red: 0.75, green: 0.68, blue: 0.59) : Color(red: 0.36, green: 0.28, blue: 0.22)
        }
        return scheme == .dark ? Color(red: 0.49, green: 0.4, blue: 0.31).opacity(0.5)
            : Color(red: 0.68, green: 0.55, blue: 0.36).opacity(0.3)
    }

    static func accentSurface(for scheme: ColorScheme, highContrast: Bool) -> Color {
        accent(for: scheme, highContrast: highContrast).opacity(highContrast ? 0.22 : 0.1)
    }

    static func accentBorder(for scheme: ColorScheme, highContrast: Bool) -> Color {
        accent(for: scheme, highContrast: highContrast).opacity(highContrast ? 1 : 0.5)
    }

    static func secondaryInk(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.76, green: 0.69, blue: 0.6) : Color(red: 0.45, green: 0.36, blue: 0.29)
    }

    static func completedCheck(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if highContrast {
            return scheme == .dark ? Color(red: 0.53, green: 0.48, blue: 0.43)
                : Color(red: 0.38, green: 0.35, blue: 0.32)
        }
        return scheme == .dark ? Color(red: 0.5, green: 0.46, blue: 0.42)
            : Color(red: 0.48, green: 0.44, blue: 0.4)
    }

    static func accentInk(for scheme: ColorScheme, highContrast: Bool) -> Color {
        scheme == .dark ? accent(for: scheme, highContrast: highContrast)
            : Color(red: highContrast ? 0.57 : 0.7, green: 0.2, blue: 0.12)
    }

    static func finishedColor(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if scheme == .dark {
            return highContrast ? Color(red: 1, green: 0.82, blue: 0.54) : Color(red: 1, green: 0.7, blue: 0.36)
        }
        return highContrast ? Color(red: 0.51, green: 0.24, blue: 0) : Color(red: 0.64, green: 0.32, blue: 0)
    }

    static func todayColor(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if scheme == .dark {
            return highContrast ? Color(red: 0.55, green: 0.94, blue: 0.75) : Color(red: 0.4, green: 0.85, blue: 0.65)
        }
        return Color(red: 0, green: highContrast ? 0.32 : 0.39, blue: 0.23)
    }
}

enum AuroraTimerAppearance {
    case idle
    case running
    case finished
}

struct AuroraPanelCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuroraInstrument.canvas(for: colorScheme)
    }
}

struct AuroraTimerBackground: View {
    let appearance: AuroraTimerAppearance

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuroraInstrument.timerSurface(for: colorScheme)
            .overlay {
                if case .finished = appearance {
                    AuroraInstrument.finishedColor(
                        for: colorScheme,
                        highContrast: accessibilitySettings.prefersHighContrast
                    ).opacity(0.1)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AuroraInstrument.stroke(
                        for: colorScheme,
                        highContrast: accessibilitySettings.prefersHighContrast
                    ))
                    .frame(height: 1)
            }
            .accessibilityHidden(true)
    }
}

struct AuroraTimerPresetSelector: View {
    let presets: [Int]
    @Binding var selection: Int

    @Namespace private var selectionPill
    @FocusState private var focusedPreset: Int?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(presets, id: \.self) { minutes in
                presetButton(minutes)
            }
        }
        .frame(height: 32)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Время таймера")
    }

    private func presetButton(_ minutes: Int) -> some View {
        let isSelected = selection == minutes
        return Button {
            select(minutes)
        } label: {
            Text(minutes == 60 ? "1 ч" : (minutes == 120 ? "2 ч" : "\(minutes)"))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(labelColor(isSelected: isSelected))
                .transaction { transaction in
                    // Only the shared pill moves; labels update immediately without ghosting.
                    transaction.animation = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        selectionBackground
                            .matchedGeometryEffect(id: "timer-preset-selection", in: selectionPill)
                    }
                }
                .overlay {
                    if focusedPreset == minutes {
                        RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius - 1)
                            .stroke(isSelected ? labelColor(isSelected: true) : AuroraInstrument.accent(
                                for: colorScheme,
                                highContrast: accessibilitySettings.prefersHighContrast
                            ), lineWidth: 2)
                            .padding(1)
                    }
                }
        }
        .buttonStyle(.plain)
        .focused($focusedPreset, equals: minutes)
        .accessibilityLabel("\(minutes) минут")
        .accessibilityValue(isSelected ? "Выбрано" : "Не выбрано")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .uiSmokeControl(
            id: "timer.duration.\(minutes)",
            action: { select(minutes) },
            value: { selection == minutes ? "selected" : "unselected" }
        )
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(AuroraInstrument.accent(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            ))
    }

    private func labelColor(isSelected: Bool) -> Color {
        guard isSelected else { return AuroraInstrument.secondaryInk(for: colorScheme) }
        return colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white
    }

    private func select(_ minutes: Int) {
        guard presets.contains(minutes), selection != minutes else { return }
        let motion = timerPresetSelectionMotion(
            reduceMotion: accessibilitySettings.prefersReducedMotion
        )
        let animation: Animation?
        switch motion {
        case .immediate:
            animation = nil
        case let .slide(duration):
            animation = .easeInOut(duration: duration)
        }
        withTransaction(Transaction(animation: animation)) {
            selection = minutes
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let currentIndex = presets.firstIndex(of: focusedPreset ?? selection) else { return }
        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = max(presets.startIndex, currentIndex - 1)
        case .right:
            nextIndex = min(presets.index(before: presets.endIndex), currentIndex + 1)
        default:
            return
        }
        let minutes = presets[nextIndex]
        focusedPreset = minutes
        select(minutes)
    }
}

struct AuroraEmptyMark: View {
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(AuroraInstrument.accent(
                    for: colorScheme,
                    highContrast: accessibilitySettings.prefersHighContrast
                ).opacity(0.12))
            Circle().stroke(AuroraInstrument.stroke(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            ), lineWidth: 1)
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct AuroraLoadingPlaceholder: View {
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            placeholder(height: 82)
            placeholder(height: 70)
        }
        .accessibilityHidden(true)
    }

    private func placeholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
            .fill(AuroraInstrument.surface(
                for: colorScheme,
                elevated: false,
                highContrast: accessibilitySettings.prefersHighContrast
            ))
            .overlay(RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius).stroke(
                AuroraInstrument.stroke(
                    for: colorScheme,
                    highContrast: accessibilitySettings.prefersHighContrast
                ),
                lineWidth: 1
            ))
            .frame(height: height)
    }
}

struct AuroraInputChrome: ViewModifier {
    let isFocused: Bool

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                    .stroke(
                        isFocused ? AuroraInstrument.accent(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ) : AuroraInstrument.stroke(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func auroraInputChrome(isFocused: Bool) -> some View {
        modifier(AuroraInputChrome(isFocused: isFocused))
    }
}
