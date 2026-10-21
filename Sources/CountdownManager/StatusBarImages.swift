import AppKit

@MainActor
package enum StatusBarImages {
    private static let marsLight = load("MarsMenuLight", template: false, fallback: "circle.fill")
    private static let marsDark = load("MarsMenuDark", template: false, fallback: "circle.fill")
    private static let calendar = load("CalendarMenu", template: true, fallback: "calendar")

    package static func image(for icon: StatusBarIcon, appearance: NSAppearance) -> NSImage? {
        switch icon {
        case .mars:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? marsDark : marsLight
        case .calendar:
            return calendar
        }
    }

    private static func load(_ name: String, template: Bool, fallback: String) -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
           let resource = NSImage(contentsOf: url) {
            image = resource
        } else {
            DiagnosticLog.shared.record("status.icon load-failure resource=\(name)")
            image = NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
        }
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = template
        return image
    }
}
