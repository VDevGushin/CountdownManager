import SwiftUI

@MainActor
final class UISmokeControlRegistry {
    struct Entry {
        let action: (() -> Void)?
        let value: (() -> String?)?
        var frame: CGRect?
        var isEnabled: Bool
        let ownerID: ObjectIdentifier?
    }

    static let shared = UISmokeControlRegistry()
    private(set) var entries: [String: Entry] = [:]
    private(set) var focusedID: String?
    private var frames: [String: CGRect] = [:]

    private init() {}

    func register(
        id: String,
        action: (() -> Void)?,
        value: (() -> String?)?,
        isEnabled: Bool,
        owner: AnyObject? = nil
    ) {
        let frame = frames[id]
        entries[id] = Entry(
            action: action,
            value: value,
            frame: frame,
            isEnabled: isEnabled,
            ownerID: owner.map(ObjectIdentifier.init)
        )
    }

    func updateFrame(_ frame: CGRect, id: String) {
        frames[id] = frame
        guard var entry = entries[id] else { return }
        entry.frame = frame
        entries[id] = entry
    }

    func remove(id: String) {
        entries.removeValue(forKey: id)
        frames.removeValue(forKey: id)
    }

    func remove(id: String, owner: AnyObject) {
        guard entries[id]?.ownerID == ObjectIdentifier(owner) else { return }
        remove(id: id)
    }

    func reset() {
        entries.removeAll()
        frames.removeAll()
        focusedID = nil
    }

    func markFocused(_ id: String) {
        focusedID = id
    }

    func press(_ id: String) -> Bool {
        guard let entry = entries[id], entry.isEnabled, let action = entry.action else { return false }
        action()
        return true
    }

    func value(_ id: String) -> String? {
        entries[id]?.value?()
    }

    func frame(_ id: String) -> CGRect? {
        frames[id]
    }

    func ids(withPrefix prefix: String) -> [String] {
        entries.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

private final class UISmokeRegistrationOwner: ObservableObject {}

private struct UISmokeFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct UISmokeControlModifier: ViewModifier {
    let id: String
    let action: (() -> Void)?
    let value: (() -> String?)?
    @StateObject private var owner = UISmokeRegistrationOwner()
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let currentValue = value?()
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UISmokeFramePreference.self,
                        value: [id: proxy.frame(in: .global)]
                    )
                }
            )
            .onAppear { register() }
            .onDisappear { UISmokeControlRegistry.shared.remove(id: id, owner: owner) }
            .onChange(of: isEnabled) { _ in register() }
            .onChange(of: currentValue) { _ in register() }
            .onPreferenceChange(UISmokeFramePreference.self) { frames in
                if let frame = frames[id] {
                    UISmokeControlRegistry.shared.updateFrame(frame, id: id)
                }
            }
    }

    private func register() {
        UISmokeControlRegistry.shared.register(
            id: id,
            action: action,
            value: value,
            isEnabled: isEnabled,
            owner: owner
        )
    }
}

extension View {
    @ViewBuilder
    func uiSmokeControl(
        id: String,
        action: (() -> Void)? = nil,
        value: (() -> String?)? = nil
    ) -> some View {
        if UISmokeConfiguration.wasRequested {
            modifier(UISmokeControlModifier(id: id, action: action, value: value))
        } else {
            self
        }
    }
}
