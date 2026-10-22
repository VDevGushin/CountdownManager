import SwiftUI

@MainActor
final class UISmokeControlRegistry {
    struct Entry {
        let action: (() -> Void)?
        var value: (() -> String?)?
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

    func updateValue(_ value: String?, id: String, owner: AnyObject) {
        guard var entry = entries[id], entry.ownerID == ObjectIdentifier(owner) else { return }
        entry.value = { value }
        entries[id] = entry
    }

    func updateEnabled(_ enabled: Bool, id: String, owner: AnyObject) {
        guard var entry = entries[id], entry.ownerID == ObjectIdentifier(owner) else { return }
        entry.isEnabled = enabled
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

private struct UISmokeRegistrationView: NSViewRepresentable {
    let id: String
    let action: (() -> Void)?
    let value: (() -> String?)?
    let observedValue: String?
    let isEnabled: Bool

    final class Coordinator {
        var id: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateRegistration(context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        updateRegistration(context.coordinator)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let id = coordinator.id {
            UISmokeControlRegistry.shared.remove(id: id, owner: coordinator)
        }
    }

    private func updateRegistration(_ coordinator: Coordinator) {
        if let previousID = coordinator.id, previousID != id {
            UISmokeControlRegistry.shared.remove(id: previousID, owner: coordinator)
        }
        coordinator.id = id
        UISmokeControlRegistry.shared.register(
            id: id, action: action, value: value, isEnabled: isEnabled, owner: coordinator
        )
    }
}

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

    private var usesNativeRegistration: Bool {
        id.hasPrefix("event.primary.") || id.hasPrefix("event.edit.")
    }

    func body(content: Content) -> some View {
        let currentValue = value?()
        content
            .background {
                if usesNativeRegistration {
                    UISmokeRegistrationView(id: id, action: action, value: value, observedValue: currentValue, isEnabled: isEnabled)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UISmokeFramePreference.self,
                        value: [id: proxy.frame(in: .global)]
                    )
                }
            )
            .onAppear {
                if !usesNativeRegistration { register(enabled: isEnabled) }
            }
            .onDisappear {
                if !usesNativeRegistration { UISmokeControlRegistry.shared.remove(id: id, owner: owner) }
            }
            .onChange(of: isEnabled) { enabled in
                UISmokeControlRegistry.shared.updateEnabled(enabled, id: id, owner: owner)
            }
            .onChange(of: currentValue) { changedValue in
                UISmokeControlRegistry.shared.updateValue(changedValue, id: id, owner: owner)
            }
            .onPreferenceChange(UISmokeFramePreference.self) { frames in
                if let frame = frames[id] {
                    UISmokeControlRegistry.shared.updateFrame(frame, id: id)
                }
            }
    }

    private func register(enabled: Bool) {
        UISmokeControlRegistry.shared.register(
            id: id, action: action, value: value, isEnabled: enabled, owner: owner
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
