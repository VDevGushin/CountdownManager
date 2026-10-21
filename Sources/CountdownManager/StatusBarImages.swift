import AppKit

@MainActor
package enum StatusBarImages {
    private static let mars = load(.mars)
    private static let calendar = load(.calendar)

    package static func image(for icon: StatusBarIcon) -> NSImage? {
        switch icon {
        case .mars: return mars
        case .calendar: return calendar
        }
    }

    private static func load(_ icon: StatusBarIcon) -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: icon.rawValue, withExtension: "pdf"),
           let resource = NSImage(contentsOf: url) {
            image = resource
        } else {
            DiagnosticLog.shared.record("status.icon load-failure resource=\(icon.rawValue)")
            image = NSImage(
                systemSymbolName: icon == .mars ? "circle.fill" : "calendar",
                accessibilityDescription: nil
            )
        }
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}
