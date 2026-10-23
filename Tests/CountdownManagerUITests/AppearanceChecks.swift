import AppKit
import CountdownManagerUI
import Foundation
import SwiftUI

@MainActor
func testApplicationAppearancePreferences() {
    let suite = "local.countdownmanager.appearance-checks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        preconditionFailure("Cannot create isolated appearance preferences")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = ApplicationAppearance(defaults: defaults)
    precondition(settings.selection == .system)
    precondition(settings.colorScheme(overriding: nil) == nil)
    precondition(settings.nativeAppearance(overriding: nil) == nil)
    precondition(defaults.object(forKey: ApplicationAppearance.preferenceKey) == nil)
    precondition(ApplicationAppearanceSelection.allCases.map(\.title) == ["Системная", "Светлая", "Тёмная"])

    for selection in ApplicationAppearanceSelection.allCases {
        settings.setSelection(selection)
        let restored = ApplicationAppearance(defaults: defaults)
        precondition(restored.selection == selection)
        let expected: ColorScheme? = selection == .system ? nil : (selection == .dark ? .dark : .light)
        precondition(settings.colorScheme(overriding: nil) == expected)
        precondition(restored.colorScheme(overriding: nil) == expected)
        for captureScheme in [ColorScheme.dark, .light] {
            precondition(settings.colorScheme(overriding: captureScheme) == captureScheme)
            precondition(settings.nativeAppearance(overriding: captureScheme)?.name
                         == (captureScheme == .dark ? NSAppearance.Name.darkAqua : .aqua))
            precondition(settings.selection == selection)
            precondition(restored.selection == selection)
        }
    }

    settings.setSelection(.system)
    precondition(ApplicationAppearance(defaults: defaults).selection == .system)
    precondition(settings.nativeAppearance(overriding: nil) == nil)
    defaults.set("future-appearance", forKey: ApplicationAppearance.preferenceKey)
    precondition(ApplicationAppearance(defaults: defaults).selection == .system)
    defaults.set(42, forKey: ApplicationAppearance.preferenceKey)
    precondition(ApplicationAppearance(defaults: defaults).selection == .system)
}
