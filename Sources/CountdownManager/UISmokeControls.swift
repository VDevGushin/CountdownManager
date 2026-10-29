import SwiftUI

@MainActor
final class UISmokeControlRegistry {
    struct Entry {
        let action: (() -> Void)?
        var value: (() -> String?)?
        var frame: CGRect?
        var isEnabled: Bool
        let ownerID: ObjectIdentifier?
        let nativeFrame: (() -> CGRect?)?
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
        owner: AnyObject? = nil,
        nativeFrame: (() -> CGRect?)? = nil
    ) {
        let frame = frames[id]
        entries[id] = Entry(
            action: action,
            value: value,
            frame: frame,
            isEnabled: isEnabled,
            ownerID: owner.map(ObjectIdentifier.init),
            nativeFrame: nativeFrame
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
        if let nativeFrame = entries[id]?.nativeFrame { return nativeFrame() }
        return frames[id]
    }

    func ids(withPrefix prefix: String) -> [String] {
        entries.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

private final class UISmokeRegistrationOwner: ObservableObject {
    weak var measuredView: NSView?
}

private struct UISmokeFrameMeasurementView: NSViewRepresentable {
    let owner: UISmokeRegistrationOwner

    final class Coordinator {
        weak var owner: UISmokeRegistrationOwner?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        bind(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        bind(view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if coordinator.owner?.measuredView === view { coordinator.owner?.measuredView = nil }
    }

    private func bind(_ view: NSView, coordinator: Coordinator) {
        if coordinator.owner !== owner, coordinator.owner?.measuredView === view {
            coordinator.owner?.measuredView = nil
        }
        coordinator.owner = owner
        owner.measuredView = view
    }
}

private struct UISmokeRegistrationView: NSViewRepresentable {
    let id: String
    let action: (() -> Void)?
    let value: (() -> String?)?
    let observedValue: String?
    let isEnabled: Bool
    let measuresNativeFrame: Bool

    final class Coordinator {
        var id: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateRegistration(context.coordinator, view: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        updateRegistration(context.coordinator, view: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let id = coordinator.id {
            UISmokeControlRegistry.shared.remove(id: id, owner: coordinator)
        }
    }

    private func updateRegistration(_ coordinator: Coordinator, view: NSView) {
        if let previousID = coordinator.id, previousID != id {
            UISmokeControlRegistry.shared.remove(id: previousID, owner: coordinator)
        }
        coordinator.id = id
        let nativeFrame: (() -> CGRect?)? = measuresNativeFrame ? { [weak view] in
            guard let view, let root = view.window?.contentView else { return nil }
            return view.convert(view.bounds, to: root)
        } : nil
        UISmokeControlRegistry.shared.register(
            id: id, action: action, value: value, isEnabled: isEnabled, owner: coordinator,
            nativeFrame: nativeFrame
        )
    }
}

private struct UISmokeFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct UISmokeControlScopeKey: EnvironmentKey {
    static let defaultValue = ""
}

private extension EnvironmentValues {
    var uiSmokeControlScope: String {
        get { self[UISmokeControlScopeKey.self] }
        set { self[UISmokeControlScopeKey.self] = newValue }
    }
}

private struct UISmokeControlModifier: ViewModifier {
    let id: String
    let action: (() -> Void)?
    let value: (() -> String?)?
    @StateObject private var owner = UISmokeRegistrationOwner()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.uiSmokeControlScope) private var scope

    private var effectiveID: String { scope + id }

    private var usesNativeRegistration: Bool {
        id.hasPrefix("event.primary.") || id.hasPrefix("event.edit.") || id.hasPrefix("desktop.event.")
            || id.hasPrefix("editor.links") || id.hasPrefix("desktop.links.") || id.hasPrefix("panel.links.")
            || id.hasPrefix("desktop.attachments.indicator.") || id.hasPrefix("desktop.summary.")
            || ["desktop.overview.header", "desktop.overview.date", "desktop.weather.overview"].contains(id)
    }

    private var measuresNativeFrame: Bool {
        switch id {
        case "desktop.overview.header", "desktop.overview.date", "desktop.weather.overview", "desktop.browser", "editor.scroll",
             "desktop.detail.identity", "desktop.detail.note", "desktop.detail.checklist": return true
        default:
            // Custom Layout placement can leave geometry preferences stale after a retained card resizes.
            return ["desktop.card.", "desktop.favorite.identity.", "desktop.favorite.metadata.",
                    "desktop.event.", "desktop.presentation.", "desktop.summary.", "desktop.collection.remaining.",
                    "desktop.date.browser.", "desktop.weather.browser.", "desktop.attachments.indicator.", "desktop.links.indicator.",
                    "editor.attachment.thumbnail.", "editor.attachment.label.",
                    "desktop.attachment.thumbnail.", "panel.attachment.thumbnail.",
                    "desktop.attachment.preview-area.", "panel.attachment.preview-area.",
                    "desktop.attachment.tile.", "panel.attachment.tile.",
                    "desktop.attachments.shelf.", "panel.attachments.shelf.",
                    "desktop.attachments.list.open.", "panel.attachments.list.open.",
                    "desktop.attachments.open.", "panel.attachments.open."]
                .contains { id.hasPrefix($0) }
        }
    }

    func body(content: Content) -> some View {
        let currentValue = value?()
        content
            .background {
                if usesNativeRegistration {
                    UISmokeRegistrationView(id: effectiveID, action: action, value: value, observedValue: currentValue,
                                            isEnabled: isEnabled, measuresNativeFrame: measuresNativeFrame)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if measuresNativeFrame {
                    UISmokeFrameMeasurementView(owner: owner)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UISmokeFramePreference.self,
                        value: [effectiveID: proxy.frame(in: .global)]
                    )
                }
            )
            .onAppear {
                if !usesNativeRegistration { register(enabled: isEnabled) }
            }
            .onDisappear {
                if !usesNativeRegistration { UISmokeControlRegistry.shared.remove(id: effectiveID, owner: owner) }
            }
            .onChange(of: effectiveID) { [previousID = effectiveID] _ in
                if !usesNativeRegistration {
                    UISmokeControlRegistry.shared.remove(id: previousID, owner: owner)
                    register(enabled: isEnabled)
                }
            }
            .onChange(of: isEnabled) { enabled in
                UISmokeControlRegistry.shared.updateEnabled(enabled, id: effectiveID, owner: owner)
            }
            .onChange(of: currentValue) { changedValue in
                UISmokeControlRegistry.shared.updateValue(changedValue, id: effectiveID, owner: owner)
            }
            .onPreferenceChange(UISmokeFramePreference.self) { frames in
                if let frame = frames[effectiveID] {
                    UISmokeControlRegistry.shared.updateFrame(frame, id: effectiveID)
                }
            }
    }

    private func register(enabled: Bool) {
        let nativeFrame: (() -> CGRect?)? = measuresNativeFrame ? { [weak owner] in
            guard let view = owner?.measuredView, let root = view.window?.contentView else { return nil }
            return view.convert(view.bounds, to: root)
        } : nil
        UISmokeControlRegistry.shared.register(
            id: effectiveID, action: action, value: value, isEnabled: enabled, owner: owner, nativeFrame: nativeFrame
        )
    }
}

extension View {
    @ViewBuilder
    func uiSmokeControlScope(_ prefix: String) -> some View {
        if UISmokeConfiguration.wasRequested {
            environment(\.uiSmokeControlScope, prefix)
        } else {
            self
        }
    }

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
