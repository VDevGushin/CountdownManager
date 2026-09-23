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
        guard UISmokeConfiguration.captureWasRequested else { return }
        isolatedCaptureOverride = highContrast
        isolatedReduceMotionOverride = reduceMotion
        prefersHighContrast = highContrast ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        prefersReducedMotion = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

enum AuroraInstrument {
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10
    static let inputCornerRadius: CGFloat = 8
    static let emojiCornerRadius: CGFloat = 6

    static let violet = Color(red: 0.39, green: 0.36, blue: 1)
    static let cyan = Color(red: 0.21, green: 0.73, blue: 1)
    static let today = Color(red: 0.03, green: 0.46, blue: 0.35)
    static let finished = Color(red: 0.64, green: 0.32, blue: 0)
    static let focus = Color(red: 0.31, green: 0.41, blue: 1)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.1)
            : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    static func surface(for scheme: ColorScheme, elevated: Bool, highContrast: Bool) -> Color {
        if scheme == .dark {
            return elevated
                ? Color(red: 0.14, green: 0.16, blue: 0.21)
                : Color(red: 0.11, green: 0.12, blue: 0.16)
        }
        return elevated || highContrast ? Color.white : Color.white.opacity(0.72)
    }

    static func stroke(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if highContrast {
            return scheme == .dark
                ? Color(red: 0.73, green: 0.76, blue: 0.82)
                : Color(red: 0.3, green: 0.33, blue: 0.39)
        }
        return scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.62)
    }

    static func accentSurface(for scheme: ColorScheme, highContrast: Bool) -> Color {
        guard highContrast else {
            return violet.opacity(scheme == .dark ? 0.2 : 0.12)
        }
        return scheme == .dark
            ? Color(red: 0.25, green: 0.24, blue: 0.44)
            : Color(red: 0.89, green: 0.88, blue: 1)
    }

    static func accentBorder(for scheme: ColorScheme, highContrast: Bool) -> Color {
        guard highContrast else { return violet.opacity(0.42) }
        return scheme == .dark
            ? Color(red: 0.71, green: 0.68, blue: 1)
            : Color(red: 0.25, green: 0.24, blue: 0.68)
    }

    static func secondaryInk(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.65, green: 0.68, blue: 0.74)
            : Color(red: 0.39, green: 0.42, blue: 0.48)
    }

    static func finishedColor(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if scheme == .dark {
            return highContrast
                ? Color(red: 1, green: 0.82, blue: 0.54)
                : Color(red: 1, green: 0.7, blue: 0.36)
        }
        return highContrast ? Color(red: 0.51, green: 0.24, blue: 0) : finished
    }

    static func todayColor(for scheme: ColorScheme, highContrast: Bool) -> Color {
        if scheme == .dark {
            return highContrast
                ? Color(red: 0.33, green: 0.88, blue: 0.69)
                : Color(red: 0.25, green: 0.84, blue: 0.64)
        }
        return highContrast ? Color(red: 0, green: 0.36, blue: 0.27) : today
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

struct AuroraCardBackground: View {
    let isPrimary: Bool

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var highContrast: Bool { accessibilitySettings.prefersHighContrast }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
        shape
            .fill(AuroraInstrument.surface(
                for: colorScheme,
                elevated: isPrimary,
                highContrast: highContrast
            ))
            .overlay {
                if isPrimary && !highContrast {
                    LinearGradient(
                        colors: [
                            AuroraInstrument.violet.opacity(colorScheme == .dark ? 0.18 : 0.1),
                            AuroraInstrument.cyan.opacity(colorScheme == .dark ? 0.12 : 0.07),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                if isPrimary && !highContrast {
                    // An overlay preserves the resolved card size; the decorative
                    // 86-point glow must not become the background's layout size.
                    Circle()
                        .fill(AuroraInstrument.cyan.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .frame(width: 86, height: 86)
                        .blur(radius: 22)
                        .offset(x: -18, y: -26)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(AuroraInstrument.stroke(for: colorScheme, highContrast: highContrast), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct AuroraEmojiBackplate: View {
    let isPrimary: Bool

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraInstrument.controlCornerRadius)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: AuroraInstrument.controlCornerRadius)
                    .stroke(AuroraInstrument.stroke(
                        for: colorScheme,
                        highContrast: accessibilitySettings.prefersHighContrast
                    ), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        if isPrimary {
            return AuroraInstrument.accentSurface(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            )
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
    }
}

struct AuroraTimerBackground: View {
    let appearance: AuroraTimerAppearance

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var highContrast: Bool { accessibilitySettings.prefersHighContrast }

    var body: some View {
        ZStack {
            baseColor
            if !highContrast {
                effectLayer
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var effectLayer: some View {
        switch appearance {
        case .idle:
            LinearGradient(
                colors: [AuroraInstrument.violet.opacity(0.1), AuroraInstrument.cyan.opacity(0.07)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .running:
            LinearGradient(
                colors: [AuroraInstrument.violet.opacity(0.18), AuroraInstrument.cyan.opacity(0.14)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .finished:
            LinearGradient(
                colors: [AuroraInstrument.finishedColor(for: colorScheme, highContrast: highContrast).opacity(0.16), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var baseColor: Color {
        switch appearance {
        case .idle:
            AuroraInstrument.surface(for: colorScheme, elevated: false, highContrast: highContrast)
        case .running:
            AuroraInstrument.surface(for: colorScheme, elevated: true, highContrast: highContrast)
        case .finished:
            if colorScheme == .dark {
                Color(red: 0.19, green: 0.14, blue: 0.1)
            } else {
                Color(red: 1, green: 0.96, blue: 0.9)
            }
        }
    }

    private var borderColor: Color {
        switch appearance {
        case .finished:
            AuroraInstrument.finishedColor(for: colorScheme, highContrast: highContrast).opacity(highContrast ? 0.7 : 0.32)
        case .idle, .running:
            AuroraInstrument.stroke(for: colorScheme, highContrast: highContrast)
        }
    }
}

struct AuroraTimerOrb: View {
    let appearance: AuroraTimerAppearance

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().stroke(AuroraInstrument.stroke(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            ), lineWidth: 1))
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch appearance {
        case .idle, .running:
            AuroraInstrument.violet.opacity(colorScheme == .dark ? 0.22 : 0.12)
        case .finished:
            AuroraInstrument.finishedColor(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            )
            .opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
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
        HStack(spacing: 0) {
            ForEach(Array(presets.enumerated()), id: \.element) { index, minutes in
                presetButton(minutes)
                if index < presets.count - 1 {
                    Rectangle()
                        .fill(AuroraInstrument.stroke(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ))
                        .frame(width: 1, height: 16)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 28)
        .background(selectorBackground)
        .clipShape(RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                .stroke(AuroraInstrument.stroke(
                    for: colorScheme,
                    highContrast: accessibilitySettings.prefersHighContrast
                ), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Время таймера")
    }

    private func presetButton(_ minutes: Int) -> some View {
        let isSelected = selection == minutes
        return Button {
            select(minutes)
        } label: {
            Text("\(minutes)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                            .stroke(AuroraInstrument.focus, lineWidth: 2)
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

    private var selectorBackground: some View {
        RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
            .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.92))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius - 1)
        if accessibilitySettings.prefersHighContrast {
            shape
                .fill(AuroraInstrument.accentSurface(for: colorScheme, highContrast: true))
                .overlay(shape.stroke(AuroraInstrument.accentBorder(
                    for: colorScheme,
                    highContrast: true
                ), lineWidth: 2))
                .padding(1)
        } else {
            shape
                .fill(
                    LinearGradient(
                        colors: [AuroraInstrument.violet, AuroraInstrument.cyan.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(1)
                .shadow(color: AuroraInstrument.violet.opacity(0.26), radius: 4, y: 1)
        }
    }

    private func labelColor(isSelected: Bool) -> Color {
        guard isSelected else { return .primary }
        if accessibilitySettings.prefersHighContrast && colorScheme == .light {
            return Color(red: 0.12, green: 0.11, blue: 0.25)
        }
        return .white
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
                .fill(AuroraInstrument.violet.opacity(colorScheme == .dark ? 0.16 : 0.08))
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
                        isFocused ? AuroraInstrument.focus : AuroraInstrument.stroke(
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
