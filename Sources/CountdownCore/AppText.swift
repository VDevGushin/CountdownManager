import Foundation

package enum AppText {
    #if SWIFT_PACKAGE
    private static let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : .module
    #else
    private static let bundle = Bundle.main
    #endif

    package static func string(_ key: String, _ arguments: String...) -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return value }
        return String(format: value, arguments: arguments)
    }
}
