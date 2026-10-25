import AppKit
import CountdownCore
import QuickLookUI
import SwiftUI

package enum AttachmentPreviewOrigin: Equatable {
    case summary
    case library
}

package struct AttachmentPreviewSelection: Equatable {
    package let eventID: UUID
    package let attachmentID: UUID
    package let origin: AttachmentPreviewOrigin

    package init(eventID: UUID, attachmentID: UUID, origin: AttachmentPreviewOrigin) {
        self.eventID = eventID
        self.attachmentID = attachmentID
        self.origin = origin
    }
}

/// Owns only the visible selection and its effects; saved files remain owned by Store.
@MainActor
package final class AttachmentPreviewSession: ObservableObject {
    package typealias URLResolver = @MainActor (EventAttachment, UUID) async -> URL?
    @Published package private(set) var selection: AttachmentPreviewSelection?
    @Published package private(set) var url: URL?
    @Published package private(set) var isResolving = false
    @Published package private(set) var isOpeningExternally = false
    @Published private(set) var rendererID = UUID()
    private var generation = UUID()
    private var resolveTask: Task<Void, Never>?
    private var externalTask: Task<Void, Never>?

    package init() {}

    package func open(event: Countdown, attachmentID: UUID, origin: AttachmentPreviewOrigin,
                      resolveURL: @escaping URLResolver) {
        guard let attachment = event.attachments.first(where: { $0.id == attachmentID }) else { return }
        invalidateEffects()
        let request = generation
        let selected = AttachmentPreviewSelection(eventID: event.id, attachmentID: attachmentID, origin: origin)
        rendererID = request
        selection = selected
        url = nil
        isResolving = true
        resolveTask = Task { @MainActor [weak self] in
            let resolved = await resolveURL(attachment, event.id)
            guard !Task.isCancelled, let self, self.generation == request, self.selection == selected else { return }
            self.url = resolved?.isFileURL == true ? resolved : nil
            self.isResolving = false
            self.resolveTask = nil
        }
    }

    package func move(by distance: Int, in event: Countdown, resolveURL: @escaping URLResolver) {
        guard let selection, selection.eventID == event.id,
              let index = event.attachments.firstIndex(where: { $0.id == selection.attachmentID }) else { return }
        let (next, overflow) = index.addingReportingOverflow(distance)
        guard !overflow, next != index, event.attachments.indices.contains(next) else { return }
        open(event: event, attachmentID: event.attachments[next].id, origin: selection.origin, resolveURL: resolveURL)
    }

    package func reconcile(event: Countdown?) {
        guard let selection else { return }
        guard let event, event.id == selection.eventID,
              event.attachments.contains(where: { $0.id == selection.attachmentID }) else {
            close()
            return
        }
    }

    package func openExternally(in event: Countdown,
                                action: @escaping @MainActor (EventAttachment, UUID) async -> Void) {
        guard !isOpeningExternally, !isResolving, url != nil, let selection,
              selection.eventID == event.id,
              let attachment = event.attachments.first(where: { $0.id == selection.attachmentID }) else { return }
        let request = generation
        isOpeningExternally = true
        externalTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await action(attachment, event.id)
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.isOpeningExternally = false
            self.externalTask = nil
        }
    }

    package func close() {
        invalidateEffects()
        url = nil
        isResolving = false
        selection = nil
    }

    /// Native dismissal keeps the last presented content until its animation completes.
    package func cancelPendingEffects() {
        invalidateEffects()
    }

    private func invalidateEffects() {
        generation = UUID()
        resolveTask?.cancel()
        resolveTask = nil
        externalTask?.cancel()
        externalTask = nil
        isOpeningExternally = false
    }

    deinit {
        resolveTask?.cancel()
        externalTask?.cancel()
    }
}

struct AttachmentPreviewView: View {
    let item: Countdown
    let compact: Bool
    @ObservedObject var session: AttachmentPreviewSession
    let back: () -> Void
    let resolveURL: AttachmentPreviewSession.URLResolver
    let openExternally: @MainActor (EventAttachment, UUID) async -> Void
    var error: String?
    var dismissError: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings

    private var prefix: String { "\(compact ? "panel" : "desktop").attachment.preview" }
    private var attachment: EventAttachment? {
        item.attachments.first { $0.id == session.selection?.attachmentID }
    }
    private var index: Int? { item.attachments.firstIndex { $0.id == session.selection?.attachmentID } }
    private var backLabel: String {
        compact ? "Назад" : (session.selection?.origin == .library ? "Вернуться к вложениям" : "Закрыть просмотр")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if compact { navigationButton }
                Text("Вложение").font(.custom("Georgia", size: 21))
                Spacer()
                if !compact { navigationButton }
            }
            .padding(.horizontal, 16).frame(height: 49)
            Divider()
            if let error {
                HStack(alignment: .top, spacing: 10) {
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Понятно", action: dismissError)
                }
                .padding(12).background(Color.red.opacity(0.1))
                .uiSmokeControl(id: prefix + ".error", value: { error })
            }
            HStack(alignment: .top, spacing: 12) {
                Text(attachment?.name ?? "Вложение")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(attachment?.name ?? "Вложение")
                    .uiSmokeControl(id: prefix + ".name", value: { attachment?.name })
                Text(index.map { "\($0 + 1) из \(item.attachments.count)" } ?? "")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                    .uiSmokeControl(id: prefix + ".position", value: {
                        index.map { "\($0 + 1)/\(item.attachments.count)" }
                    })
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 56, alignment: .top)
            previewCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            HStack(spacing: 8) {
                moveButton(distance: -1, symbol: "chevron.left", label: "Предыдущее вложение")
                moveButton(distance: 1, symbol: "chevron.right", label: "Следующее вложение")
                Spacer(minLength: 8)
                Button("Открыть в приложении", action: performExternalOpen)
                    .font(.system(size: 12))
                    .accessibilityIdentifier(prefix + ".external")
                    .uiSmokeControl(id: prefix + ".external", action: performExternalOpen)
                    .disabled(session.url == nil || session.isResolving || session.isOpeningExternally)
            }
            .padding(16)
        }
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
        .background(AuroraPanelCanvas())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(prefix)
        .uiSmokeControl(id: prefix, value: { session.selection?.attachmentID.uuidString })
    }

    private var previewCanvas: some View {
        ZStack {
            AuroraInstrument.surface(for: colorScheme, elevated: false,
                                     highContrast: accessibilitySettings.prefersHighContrast)
            if let url = session.url, session.selection != nil {
                AttachmentNativePreview(url: url)
                    .id(session.rendererID)
            } else if session.isResolving {
                ProgressView("Открываем копию…").font(.system(size: 12))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc").font(.system(size: 28)).accessibilityHidden(true)
                    Text("Копия недоступна").font(.system(size: 13, weight: .medium))
                    Text("Исходный файл не изменён.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .uiSmokeControl(id: prefix + ".canvas", value: {
            session.isResolving ? "resolving" : (session.url == nil ? "unavailable" : "native-preview-requested")
        })
    }

    private var navigationButton: some View {
        Button(action: back) {
            Image(systemName: compact ? "chevron.left" : "xmark")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(backLabel).help(backLabel)
        .accessibilityIdentifier(prefix + ".back")
        .uiSmokeControl(id: prefix + ".back", action: back)
    }

    private func moveButton(distance: Int, symbol: String, label: String) -> some View {
        let destination = (index ?? -2) + distance
        let canMove = index != nil && item.attachments.indices.contains(destination)
        return Button { session.move(by: distance, in: item, resolveURL: resolveURL) } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 16, height: 20)
        }
        .accessibilityLabel(label).help(label)
        .accessibilityIdentifier(prefix + (distance < 0 ? ".previous" : ".next"))
        .uiSmokeControl(id: prefix + (distance < 0 ? ".previous" : ".next"), action: {
            guard canMove else { return }
            session.move(by: distance, in: item, resolveURL: resolveURL)
        })
        .disabled(!canMove)
    }

    private func performExternalOpen() {
        session.openExternally(in: item, action: openExternally)
    }
}

/// A renderer belongs to one selected file and is never reused after Quick Look closes it.
private struct AttachmentNativePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AttachmentPreviewHostView {
        AttachmentPreviewHostView(url: url)
    }

    func updateNSView(_ nsView: AttachmentPreviewHostView, context: Context) {
        nsView.setURL(url)
    }

    static func dismantleNSView(_ nsView: AttachmentPreviewHostView, coordinator: ()) {
        nsView.shutdown()
    }
}

/// The retained panel can hide without destroying SwiftUI. Its renderer must not play media while hidden.
private final class AttachmentPreviewHostView: NSView {
    private var url: URL
    private var preview: QLPreviewView?
    private var visibilityObservation: NSKeyValueObservation?
    private var closeObservation: NSObjectProtocol?
    private var isShutdown = false

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        stopRenderer()
        guard !isShutdown, let window else { return }
        visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.updateVisibility(window.isVisible) }
        }
        closeObservation = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                  object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRenderer() }
        }
    }

    func setURL(_ newURL: URL) {
        guard url != newURL else { return }
        stopRenderer()
        url = newURL
        updateVisibility(window?.isVisible == true)
    }

    func shutdown() {
        isShutdown = true
        stopObservingWindow()
        stopRenderer()
    }

    private func stopObservingWindow() {
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let closeObservation { NotificationCenter.default.removeObserver(closeObservation) }
        closeObservation = nil
    }

    private func updateVisibility(_ isVisible: Bool) {
        guard isVisible, !isShutdown else {
            stopRenderer()
            return
        }
        guard preview == nil, let preview = QLPreviewView(frame: bounds, style: .normal) else { return }
        preview.shouldCloseWithWindow = false
        preview.autostarts = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.preview = preview
        preview.previewItem = url as NSURL
    }

    private func stopRenderer() {
        preview?.close()
        preview?.removeFromSuperview()
        preview = nil
    }
}
