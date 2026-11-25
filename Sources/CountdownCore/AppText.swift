import Foundation
import os

package enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case russian = "ru"

    private static let preferenceKey = "app.language"

    package static func selection(in defaults: UserDefaults) -> AppLanguage? {
        defaults.string(forKey: preferenceKey).flatMap(AppLanguage.init(rawValue:))
    }

    package func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    package var title: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    package var locale: Locale {
        Locale(identifier: self == .russian ? "ru_RU" : "en_US")
    }
}

package enum AppText {
    #if SWIFT_PACKAGE
    private static let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : .module
    #else
    private static let bundle = Bundle.main
    #endif

    private static let launchLanguageKey = "CountdownLaunchLanguage"

    @MainActor package static func prepareLaunch(defaults: UserDefaults) {
        setLanguage(launchOverride ?? AppLanguage.selection(in: defaults) ?? .english)
    }

    private static var launchOverride: AppLanguage? {
        UserDefaults.standard.string(forKey: launchLanguageKey).flatMap(AppLanguage.init(rawValue:))
    }

    private static let activeLanguage = OSAllocatedUnfairLock(initialState: launchOverride ?? AppLanguage.english)

    package static var language: AppLanguage { activeLanguage.withLock { $0 } }

    @MainActor package static func setLanguage(_ selection: AppLanguage) {
        activeLanguage.withLock { $0 = selection }
    }

    private static let russianBundle = localizedBundle(.russian)
    private static let englishBundle = localizedBundle(.english)

    private static func localizedBundle(_ language: AppLanguage) -> Bundle? {
        bundle.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    package static func string(_ key: String, _ arguments: String...) -> String {
        let language = Self.language
        let localized = language == .english ? englishBundle : russianBundle
        let fallback = englishBundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
        let value = localized?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: language.locale, arguments: arguments)
    }

    package static func pluralCategory(_ count: Int) -> PluralCategory {
        if language == .english { return count.magnitude == 1 ? .one : .many }
        let tail = count.magnitude % 100
        if (11...14).contains(tail) { return .many }
        switch count.magnitude % 10 {
        case 1: return .one
        case 2...4: return .few
        default: return .many
        }
    }

    package enum PluralCategory {
        case one, few, many
    }
}
