import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    let back: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: back) {
                    Label("Назад", systemImage: "chevron.left")
                }
                .font(.system(size: 12))
                .accessibilityIdentifier("settings.back")
                .uiSmokeControl(id: "settings.back", action: back)
                Text("Настройки").font(.custom("Georgia", size: 22)).tracking(-0.8)
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Автопроверка обновлений", isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.automaticallyChecksForUpdates = $0 }
                        ))
                        .disabled(!updates.isAvailable)
                        .accessibilityIdentifier("updates.automatic-checks")
                        hint(updates.isAvailable
                             ? "Ручная проверка доступна и при выключенной автопроверке."
                             : "Канал обновлений в этой сборке не настроен.")
                    }

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
                        hint("Выбор сохраняется. При следующем запуске включённый режим восстановится.")
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

                    VStack(alignment: .leading, spacing: 8) {
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
                        .accessibilityIdentifier("settings.weather.location")
                        .uiSmokeControl(id: "settings.weather.location", value: { weather.locationTitle })
                        .disabled(!weather.enabled)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if updates.isInstallationDeferred {
                            Button("Обновление готово · установить…") { updates.installDeferredUpdate(nil) }
                                .accessibilityIdentifier("updates.install")
                                .uiSmokeControl(id: "updates.install", action: { updates.installDeferredUpdate(nil) })
                        } else {
                            Button("Проверить обновления…") { updates.checkForUpdates(nil) }
                                .disabled(!updates.canCheckForUpdates)
                                .accessibilityIdentifier("updates.check")
                                .uiSmokeControl(id: "updates.check", action: { updates.checkForUpdates(nil) })
                        }
                        Button("Диагностика…") { store.openDiagnostics() }
                            .accessibilityIdentifier("settings.diagnostics")
                    }
                    if let version = applicationVersionLabel() {
                        Text(version)
                            .font(.system(size: 11))
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                            .accessibilityIdentifier("settings.version")
                            .uiSmokeControl(id: "settings.version", value: { version })
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraPanelCanvas())
        .accessibilityIdentifier("settings.screen")
        .uiSmokeControl(id: "settings.screen")
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12))
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}
