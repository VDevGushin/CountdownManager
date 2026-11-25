import AppKit
import ServiceManagement
import SwiftUI
import CountdownCore

package enum ApplicationAppearanceSelection: String, CaseIterable {
    case system, light, dark

    package var title: String {
        switch self {
        case .system: AppText.string("settings.appearance.system")
        case .light: AppText.string("settings.appearance.light")
        case .dark: AppText.string("settings.appearance.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
package final class ApplicationAppearance: ObservableObject {
    package static let preferenceKey = "appearance.selection"
    @Published package private(set) var selection: ApplicationAppearanceSelection
    private let defaults: UserDefaults

    package init(defaults: UserDefaults) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.preferenceKey)
            .flatMap(ApplicationAppearanceSelection.init(rawValue:)) ?? .system
    }

    package func setSelection(_ selection: ApplicationAppearanceSelection) {
        guard self.selection != selection else { return }
        defaults.set(selection.rawValue, forKey: Self.preferenceKey)
        self.selection = selection
    }

    package func colorScheme(overriding captureOverride: ColorScheme?) -> ColorScheme? {
        captureOverride ?? selection.colorScheme
    }

    package func nativeAppearance(overriding captureOverride: ColorScheme?) -> NSAppearance? {
        colorScheme(overriding: captureOverride).flatMap { scheme in
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    let diagnosticsContext: () -> DiagnosticExportContext
    var showWhatsNew: () -> Void = {}
    let back: () -> Void
    var backShortcut: KeyboardShortcut?
    var showsCloseButton = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @EnvironmentObject private var appearanceSettings: ApplicationAppearance

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !showsCloseButton { navigationButton }
                Text(AppText.string("settings.title")).font(.custom("Georgia", size: 21))
                Spacer()
                if showsCloseButton { navigationButton }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 49)
            .overlay(alignment: .bottom) { separator }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup(AppText.string("settings.app")) {
                        appearanceChoice
                        loginChoice
                        Toggle(AppText.string("settings.updates"), isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.automaticallyChecksForUpdates = $0 }
                        ))
                        .disabled(!updates.isAvailable)
                        .accessibilityIdentifier("updates.automatic-checks")
                        if !updates.isAvailable { hint(AppText.string("settings.updateChannelUnavailable")) }
                        keepAwakeChoice
                    }
                    separator
                    settingsGroup(AppText.string("settings.weather")) {
                        Toggle(AppText.string("settings.showWeather"), isOn: Binding(
                            get: { weather.enabled }, set: { weather.setEnabled($0) }
                        ))
                        .accessibilityIdentifier("settings.weather.enabled")
                        .uiSmokeControl(
                            id: "settings.weather.enabled", action: { weather.setEnabled(!weather.enabled) },
                            value: { weather.enabled ? "on" : "off" }
                        )
                        Picker(AppText.string("settings.city"), selection: Binding(
                            get: { weather.location }, set: { weather.selectLocation($0) }
                        )) {
                            Text(AppText.string("common.automatic")).tag(WeatherLocationSelection.automatic)
                            ForEach(WeatherCity.allCases, id: \.self) { city in
                                Text(city.title).tag(WeatherLocationSelection.city(city))
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.leading, 20)
                        .accessibilityIdentifier("settings.weather.location")
                        .uiSmokeControl(id: "settings.weather.location", value: { weather.locationTitle })
                        .disabled(!weather.enabled)
                    }
                    separator
                    settingsGroup(AppText.string("settings.service")) {
                        updateAction
                        Button(action: saveDiagnostics) {
                            HStack(spacing: 8) {
                                actionLabel(AppText.string("settings.saveDiagnostics"), symbol: "doc.text")
                                if store.isExportingDiagnostics { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(store.isExportingDiagnostics)
                        .accessibilityIdentifier("settings.diagnostics")
                        .uiSmokeControl(id: "settings.diagnostics", action: saveDiagnostics)
                        Button(action: showWhatsNew) {
                            actionLabel(AppText.string("app.menu.whatsNew"), symbol: "doc.text")
                        }
                        .disabled(store.isExportingDiagnostics || store.hasPendingPersistence || updates.isPresentingUpdateUI)
                        .accessibilityIdentifier("settings.whats-new")
                        .uiSmokeControl(id: "settings.whats-new", action: showWhatsNew)
                    }
                    if let version = applicationVersionLabel() {
                        Text(version)
                            .font(.system(size: 11))
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                            .padding(.top, 3)
                            .accessibilityIdentifier("settings.version")
                            .uiSmokeControl(id: "settings.version", value: { version })
                    }
                }
                .toggleStyle(.checkbox)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraPanelCanvas())
        .accessibilityIdentifier("settings.screen")
        .uiSmokeControl(id: "settings.screen")
    }

    private var navigationButton: some View {
        Button(action: back) {
            Image(systemName: showsCloseButton ? "xmark" : "chevron.left")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
        }
        .keyboardShortcut(backShortcut)
        .accessibilityLabel(showsCloseButton ? AppText.string("settings.close") : AppText.string("common.back"))
        .accessibilityIdentifier(showsCloseButton ? "settings.close" : "settings.back")
        .uiSmokeControl(id: showsCloseButton ? "settings.close" : "settings.back", action: back)
    }

    private var appearanceChoice: some View {
        Picker(AppText.string("settings.theme"), selection: Binding(
            get: { appearanceSettings.selection }, set: { appearanceSettings.setSelection($0) }
        )) {
            ForEach(ApplicationAppearanceSelection.allCases, id: \.self) { selection in
                Text(selection.title).tag(selection)
                    .uiSmokeControl(id: "settings.appearance.\(selection.rawValue)",
                                    action: { appearanceSettings.setSelection(selection) })
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("settings.appearance")
        .uiSmokeControl(id: "settings.appearance", value: { appearanceSettings.selection.rawValue })
    }

    private var loginChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(AppText.string("settings.loginItem"), isOn: Binding(
                get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                set: { store.setLogin($0) }
            ))
            .disabled(!store.loginItemManagementIsAvailable)
            .accessibilityIdentifier("settings.login")
            if store.loginStatus == .requiresApproval {
                Button(AppText.string("settings.loginPermission")) { store.openLoginItemSettings() }
                    .font(.system(size: 12))
                    .disabled(!store.loginItemManagementIsAvailable)
                    .accessibilityIdentifier("settings.login-approval")
            }
        }
    }

    private var keepAwakeChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(AppText.string("settings.keepAwake"), isOn: Binding(
                get: { keepAwake.isEnabled }, set: { keepAwake.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.keep-awake")
            .uiSmokeControl(
                id: "settings.keep-awake",
                action: { keepAwake.setEnabled(!keepAwake.isEnabled) },
                value: { keepAwake.isEnabled ? "on" : "off" }
            )
            hint(AppText.string("settings.keepAwakeRestores"))
            if let error = keepAwake.error {
                Text(error).font(.system(size: 12))
                    .foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("settings.keep-awake.error")
            }
            if keepAwake.canDisableRestoration {
                Button(AppText.string("settings.keepAwakeDoNotRestore")) { keepAwake.setEnabled(false) }
                    .font(.system(size: 12))
                    .accessibilityIdentifier("settings.keep-awake.cancel-restoration")
                    .uiSmokeControl(id: "settings.keep-awake.cancel-restoration", action: { keepAwake.setEnabled(false) })
            }
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        if updates.isInstallationDeferred {
            Button { updates.installDeferredUpdate(nil) } label: {
                actionLabel(AppText.string("update.installButton"), symbol: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("updates.install")
            .uiSmokeControl(id: "updates.install", action: { updates.installDeferredUpdate(nil) })
        } else {
            Button { updates.checkForUpdates(nil) } label: {
                actionLabel(AppText.string("app.menu.checkForUpdates"), symbol: "arrow.triangle.2.circlepath")
            }
            .disabled(!updates.canCheckForUpdates)
            .accessibilityIdentifier("updates.check")
            .uiSmokeControl(id: "updates.check", action: { updates.checkForUpdates(nil) })
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            content()
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Rectangle()
            .fill(AuroraInstrument.stroke(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11))
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
    }

    private func saveDiagnostics() {
        weather.recordDiagnosticSnapshot(reason: .diagnostics)
        store.saveDiagnostics(context: diagnosticsContext)
    }
}
