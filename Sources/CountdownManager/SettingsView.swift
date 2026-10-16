import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    let diagnosticsContext: () -> DiagnosticExportContext
    let back: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 26)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Назад")
                .accessibilityIdentifier("settings.back")
                .uiSmokeControl(id: "settings.back", action: back)
                Text("Настройки").font(.custom("Georgia", size: 21))
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 49)
            .overlay(alignment: .bottom) { separator }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup("Приложение") {
                        loginChoice
                        Toggle("Автопроверка обновлений", isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.automaticallyChecksForUpdates = $0 }
                        ))
                        .disabled(!updates.isAvailable)
                        .accessibilityIdentifier("updates.automatic-checks")
                        if !updates.isAvailable { hint("Канал обновлений в этой сборке не настроен.") }
                        keepAwakeChoice
                    }
                    separator
                    settingsGroup("Погода") {
                        Toggle("Показывать погоду в днях", isOn: Binding(
                            get: { weather.enabled }, set: { weather.setEnabled($0) }
                        ))
                        .accessibilityIdentifier("settings.weather.enabled")
                        .uiSmokeControl(
                            id: "settings.weather.enabled", action: { weather.setEnabled(!weather.enabled) },
                            value: { weather.enabled ? "on" : "off" }
                        )
                        Picker("Город", selection: Binding(
                            get: { weather.location }, set: { weather.selectLocation($0) }
                        )) {
                            Text("Автоматически").tag(WeatherLocationSelection.automatic)
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
                    settingsGroup("Обслуживание") {
                        updateAction
                        Button(action: saveDiagnostics) {
                            HStack(spacing: 8) {
                                actionLabel("Сохранить диагностику…", symbol: "doc.text")
                                if store.isExportingDiagnostics { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(store.isExportingDiagnostics)
                        .accessibilityIdentifier("settings.diagnostics")
                        .uiSmokeControl(id: "settings.diagnostics", action: saveDiagnostics)
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

    private var loginChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Запускать при входе в macOS", isOn: Binding(
                get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                set: { store.setLogin($0) }
            ))
            .disabled(!store.loginItemManagementIsAvailable)
            .accessibilityIdentifier("settings.login")
            if store.loginStatus == .requiresApproval {
                Button("Разрешить в настройках macOS…") { store.openLoginItemSettings() }
                    .font(.system(size: 12))
                    .disabled(!store.loginItemManagementIsAvailable)
                    .accessibilityIdentifier("settings.login-approval")
            }
        }
    }

    private var keepAwakeChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Не давать Mac и экрану засыпать", isOn: Binding(
                get: { keepAwake.isEnabled }, set: { keepAwake.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.keep-awake")
            .uiSmokeControl(
                id: "settings.keep-awake",
                action: { keepAwake.setEnabled(!keepAwake.isEnabled) },
                value: { keepAwake.isEnabled ? "on" : "off" }
            )
            hint("Выбор сохраняется. Включённый режим восстановится при следующем запуске.")
            if let error = keepAwake.error {
                Text(error).font(.system(size: 12))
                    .foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("settings.keep-awake.error")
            }
            if keepAwake.canDisableRestoration {
                Button("Не включать при запуске") { keepAwake.setEnabled(false) }
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
                actionLabel("Обновление готово · установить…", symbol: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("updates.install")
            .uiSmokeControl(id: "updates.install", action: { updates.installDeferredUpdate(nil) })
        } else {
            Button { updates.checkForUpdates(nil) } label: {
                actionLabel("Проверить обновления…", symbol: "arrow.triangle.2.circlepath")
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
