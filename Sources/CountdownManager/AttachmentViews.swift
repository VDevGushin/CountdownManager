import CountdownCore
import SwiftUI
import UniformTypeIdentifiers

private func attachmentFileSymbol(_ attachment: EventAttachment) -> String {
    guard let type = UTType(filenameExtension: (attachment.name as NSString).pathExtension) else { return "doc" }
    if type.conforms(to: .image) { return "photo" }
    if type.conforms(to: .movie) { return "film" }
    if type.conforms(to: .audio) { return "waveform" }
    if type.conforms(to: .pdf) { return "doc.richtext" }
    return "doc"
}

/// Releases draft-only copies when the editor hierarchy is actually destroyed, not when its window hides.
final class EditorAttachmentSession: ObservableObject {
    let id = UUID()
    private var cleanup: (() -> Void)?
    private var importTask: Task<Void, Never>?

    @MainActor func importFiles(
        in store: Store,
        currentAttachments: [EventAttachment],
        sources: [URL]? = nil,
        retaining stagedFiles: [StagedMaterialFile] = [],
        completion: @escaping @MainActor ([EventAttachment]) -> Void
    ) {
        guard importTask == nil else { return }
        if cleanup == nil {
            let draftID = id
            cleanup = { Task { @MainActor in await store.discardAttachmentDraft(draftID) } }
        }
        let draftID = id
        importTask = Task { @MainActor [weak self] in
            defer { withExtendedLifetime(stagedFiles) {} }
            guard !Task.isCancelled, self != nil else { return }
            let prepared = await store.beginAttachmentDraft(draftID)
            guard !Task.isCancelled, self != nil else { return }
            var attachments: [EventAttachment] = []
            if prepared {
                if let sources {
                    attachments = await store.importAttachments(from: sources, draftID: draftID,
                                                                 currentAttachments: currentAttachments)
                } else {
                    attachments = await store.chooseAttachments(draftID: draftID, currentAttachments: currentAttachments)
                }
            }
            guard !Task.isCancelled, self != nil else { return }
            self?.importTask = nil
            completion(attachments)
        }
    }

    @MainActor func prepare(in store: Store) async -> Bool {
        if cleanup == nil {
            let draftID = id
            cleanup = { Task { @MainActor in await store.discardAttachmentDraft(draftID) } }
        }
        return await store.beginAttachmentDraft(id)
    }

    @MainActor func cancel() {
        importTask?.cancel()
        importTask = nil
        cleanup?()
        cleanup = nil
    }

    @MainActor func discard(in store: Store) async {
        await store.discardAttachmentDraft(id)
        cleanup = nil
    }

    deinit {
        importTask?.cancel()
        cleanup?()
    }
}

struct AttachmentFileLabel: View {
    let attachment: EventAttachment
    var thumbnailURL: (@MainActor () async -> URL?)?
    var thumbnailControlID: String?
    var compactControlID: String?
    var thumbnailSize: CGFloat = 44

    private var symbol: String {
        attachmentFileSymbol(attachment)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let thumbnailURL, let thumbnailControlID {
                AttachmentThumbnail(attachment: attachment, fallbackSymbol: symbol,
                                    controlID: thumbnailControlID, resolveURL: thumbnailURL, pointSize: thumbnailSize)
            } else {
                if let compactControlID {
                    compactIcon.uiSmokeControl(id: compactControlID + ".icon")
                } else {
                    compactIcon
                }
            }
            if let compactControlID {
                fileText.uiSmokeControl(id: compactControlID + ".text")
            } else {
                fileText
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .help(attachment.name)
    }

    private var compactIcon: some View {
        Image(systemName: symbol)
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)
    }

    private var fileText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.name).lineLimit(2).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct SavedAttachmentSection: View {
    let item: Countdown
    let compact: Bool
    let open: (EventAttachment) -> Void
    var thumbnailURL: (@MainActor (EventAttachment) async -> URL?)?
    var showAll: () -> Void = {}
    @State private var expanded = false
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var surface: String { compact ? "panel" : "desktop" }
    private var summaryCount: Int { compact ? 3 : 4 }
    private var shelfColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: compact ? 8 : 10,
                                  alignment: .leading), count: compact ? 3 : 2)
    }

    var body: some View {
        if !item.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if compact {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .medium))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                                .accessibilityHidden(true)
                            heading
                            Spacer()
                            Text(String(item.attachments.count))
                                .font(.system(size: 11))
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        }
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Вложения: \(item.attachments.count), \(expanded ? "свернуть" : "раскрыть")")
                    .accessibilityIdentifier("panel.attachments.toggle.\(item.id.uuidString)")
                    .uiSmokeControl(id: "panel.attachments.toggle.\(item.id.uuidString)",
                                    action: { expanded.toggle() }, value: { expanded ? "expanded" : "collapsed" })
                } else {
                    SavedMaterialHeading(title: "Вложения", count: item.attachments.count, symbolName: "paperclip",
                                         controlPrefix: "desktop.attachments", eventID: item.id)
                }
                if !compact || expanded {
                    LazyVGrid(columns: shelfColumns, alignment: .leading, spacing: compact ? 8 : 10) {
                        ForEach(Array(item.attachments.prefix(summaryCount))) { attachment in
                            Button { open(attachment) } label: {
                                AttachmentShelfTile(attachment: attachment, compact: compact,
                                                    controlPrefix: "\(surface).attachment",
                                                    eventID: item.id,
                                                    thumbnailURL: thumbnailURL.map { resolve in { await resolve(attachment) } })
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Просмотреть вложение: \(attachment.name)")
                            .accessibilityIdentifier("attachments.open.\(item.id.uuidString).\(attachment.id.uuidString)")
                            .uiSmokeControl(id: "\(surface).attachments.open.\(item.id.uuidString).\(attachment.id.uuidString)",
                                            action: { open(attachment) })
                        }
                    }
                    .frame(maxWidth: compact ? .infinity : 490, alignment: .leading)
                    .uiSmokeControl(id: "\(surface).attachments.shelf.\(item.id.uuidString)")
                    if item.attachments.count > summaryCount {
                        Button("Показать все \(item.attachments.count)", action: showAll)
                            .buttonStyle(.plain)
                            .foregroundStyle(AuroraInstrument.accent(
                                for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                            ))
                            .accessibilityIdentifier("\(surface).attachments.all.\(item.id.uuidString)")
                            .uiSmokeControl(id: "\(surface).attachments.all.\(item.id.uuidString)", action: showAll)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(surface).attachments.\(item.id.uuidString)")
            .uiSmokeControl(id: "\(surface).attachments.\(item.id.uuidString)", value: { String(item.attachments.count) })
        }
    }

    private var heading: some View {
        Text("Вложения")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
            .uiSmokeControl(id: "\(surface).attachments.heading.\(item.id.uuidString)")
    }
}

private struct AttachmentShelfTile: View {
    let attachment: EventAttachment
    let compact: Bool
    let controlPrefix: String
    let eventID: UUID
    let thumbnailURL: (@MainActor () async -> URL?)?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings

    private var identity: String { "\(eventID.uuidString).\(attachment.id.uuidString)" }
    private var previewHeight: CGFloat { compact ? 68 : 88 }
    private var metadata: String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)
        let fileExtension = (attachment.name as NSString).pathExtension.uppercased()
        return fileExtension.isEmpty ? size : "\(fileExtension) · \(size)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                AttachmentThumbnail(attachment: attachment, fallbackSymbol: attachmentFileSymbol(attachment),
                                    controlID: "\(controlPrefix).thumbnail.\(identity)",
                                    resolveURL: { await thumbnailURL?() },
                                    pointSize: max(geometry.size.width, previewHeight),
                                    canvasSize: CGSize(width: geometry.size.width, height: previewHeight),
                                    showsUnavailableLabel: true)
            }
            .frame(height: previewHeight)
            .uiSmokeControl(id: "\(controlPrefix).preview-area.\(identity)")
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.name)
                    .font(.system(size: compact ? 11 : 12, weight: compact ? .regular : .medium))
                    .lineLimit(2).truncationMode(.middle)
                    .frame(height: compact ? 28 : 30, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(compact ? 0 : 8)
            .padding(.top, compact ? 6 : 0)
        }
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                             highContrast: accessibilitySettings.prefersHighContrast))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if !compact || accessibilitySettings.prefersHighContrast {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AuroraInstrument.stroke(for: colorScheme,
                                                     highContrast: accessibilitySettings.prefersHighContrast), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .help(attachment.name)
        .uiSmokeControl(id: "\(controlPrefix).tile.\(identity)")
    }
}

struct AttachmentListView: View {
    let item: Countdown
    let compact: Bool
    let back: () -> Void
    let open: (EventAttachment) -> Void
    let thumbnailURL: @MainActor (EventAttachment) async -> URL?
    var error: String?
    var dismissError: () -> Void = {}
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings

    private var prefix: String { "\(compact ? "panel" : "desktop").attachments.list" }
    private var filtered: [EventAttachment] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? item.attachments : item.attachments.filter { $0.name.localizedStandardContains(needle) }
    }

    private var summary: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Файлов: \(item.attachments.count)"
            : "Найдено: \(filtered.count) из \(item.attachments.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if compact { navigationButton }
                Text(compact ? "Вложения" : "Вложение")
                    .font(.custom("Georgia", size: 21))
                    .uiSmokeControl(id: "\(prefix).title.\(item.id)", value: { compact ? "Вложения" : "Вложение" })
                Spacer()
                if !compact { navigationButton }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 49)
            Divider()
            if let error {
                HStack(alignment: .top, spacing: 10) {
                    Text(error).font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Понятно", action: dismissError)
                        .accessibilityIdentifier("\(prefix).error.dismiss.\(item.id)")
                        .uiSmokeControl(id: "\(prefix).error.dismiss.\(item.id)", action: dismissError)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .accessibilityIdentifier("\(prefix).error.\(item.id)")
                .uiSmokeControl(id: "\(prefix).error.\(item.id)", value: { error })
            }
            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12)
            HStack(spacing: 8) {
                TextField("Найти файл", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel("Найти файл")
                    .accessibilityIdentifier("\(prefix).search.\(item.id)")
                    .uiSmokeControl(id: "\(prefix).search.\(item.id)", action: { searchFocused = true }, value: { query })
                Button("Очистить") { query = "" }
                    .disabled(query.isEmpty)
                    .accessibilityIdentifier("\(prefix).clear.\(item.id)")
                    .uiSmokeControl(id: "\(prefix).clear.\(item.id)", action: { query = "" })
            }
            .padding(16)
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("Ничего не найдено").font(.system(size: 13, weight: .medium))
                    Text("Измените запрос или очистите поиск.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("\(prefix).empty.\(item.id)")
                .uiSmokeControl(id: "\(prefix).empty.\(item.id)")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filtered) { attachment in
                            Button { open(attachment) } label: {
                                AttachmentFileLabel(
                                    attachment: attachment,
                                    thumbnailURL: { await thumbnailURL(attachment) },
                                    thumbnailControlID: "\(compact ? "panel" : "desktop").attachment.list.thumbnail.\(item.id).\(attachment.id)",
                                    thumbnailSize: compact ? 36 : 44
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Открыть вложение: \(attachment.name)")
                            .accessibilityIdentifier("\(prefix).open.\(item.id).\(attachment.id)")
                            .uiSmokeControl(id: "\(prefix).open.\(item.id).\(attachment.id)", action: { open(attachment) })
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
            Divider()
            Text(summary)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .uiSmokeControl(id: "\(prefix).summary.\(item.id)", value: { summary })
        }
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
        .background(AuroraPanelCanvas())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(prefix).\(item.id)")
        .uiSmokeControl(id: "\(prefix).\(item.id)", value: { "\(filtered.count)/\(item.attachments.count)" })
    }

    private var navigationButton: some View {
        Button(action: back) {
            Image(systemName: compact ? "chevron.left" : "xmark")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(compact ? "Назад" : "Закрыть вложения")
        .help(compact ? "Назад" : "Закрыть вложения")
        .accessibilityIdentifier("\(prefix).\(compact ? "back" : "close").\(item.id)")
        .uiSmokeControl(id: "\(prefix).\(compact ? "back" : "close").\(item.id)", action: back)
    }

}

struct EditorAttachmentSection: View {
    @Binding var attachments: [EventAttachment]
    let keepsAfterDate: Bool
    let isImporting: Bool
    let add: () -> Void
    let thumbnailURL: @MainActor (EventAttachment) async -> URL?
    @Environment(\.colorScheme) private var colorScheme

    private var atLimit: Bool { attachments.count >= EventAttachment.maximumCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Вложения").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                    .uiSmokeControl(id: "editor.attachments.heading")
                Spacer()
                Text("\(attachments.count)/\(EventAttachment.maximumCount)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .uiSmokeControl(id: "editor.attachments.count", value: {
                        "\(attachments.count)/\(EventAttachment.maximumCount)"
                    })
            }
            HStack {
                Button("Добавить файлы…", action: add)
                    .accessibilityIdentifier("editor.attachments.add")
                    .uiSmokeControl(id: "editor.attachments.add", action: add)
                    .disabled(isImporting || atLimit)
                if isImporting {
                    ProgressView().controlSize(.small)
                    Text("Добавляем копии…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if atLimit {
                Text(attachments.count > EventAttachment.maximumCount
                     ? "Сохранённые файлы останутся. Чтобы добавить новые, оставьте меньше \(EventAttachment.maximumCount)."
                     : "Достигнут лимит \(EventAttachment.maximumCount) файлов. Уберите файл, чтобы добавить другой.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .uiSmokeControl(id: "editor.attachments.limit", value: { String(attachments.count) })
            }
            ForEach(attachments) { attachment in
                HStack(spacing: 8) {
                    AttachmentFileLabel(attachment: attachment,
                                        thumbnailURL: { await thumbnailURL(attachment) },
                                        thumbnailControlID: "editor.attachment.thumbnail.\(attachment.id.uuidString)",
                                        compactControlID: "editor.attachment.label.\(attachment.id.uuidString)",
                                        thumbnailSize: 36)
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "minus.circle").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать вложение: \(attachment.name)")
                    .accessibilityIdentifier("editor.attachments.remove.\(attachment.id.uuidString)")
                    .uiSmokeControl(id: "editor.attachments.remove.\(attachment.id.uuidString)", action: {
                        guard !isImporting else { return }
                        attachments.removeAll { $0.id == attachment.id }
                    })
                    .disabled(isImporting)
                }
            }
            attachmentExpiryFootnote(keepsAfterDate: keepsAfterDate)
                .uiSmokeControl(id: "editor.attachments.expiry", value: { keepsAfterDate ? "retained" : "expires" })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.attachments")
        .uiSmokeControl(id: "editor.attachments", value: { String(attachments.count) })
    }
}

private func attachmentExpiryFootnote(keepsAfterDate: Bool) -> some View {
    Text(keepsAfterDate
         ? "Прикреплённые копии останутся после даты события, пока вы не удалите событие или вложения. Исходные файлы сохранятся."
         : "Прикреплённые копии удалятся вместе с событием после его даты. Исходные файлы сохранятся.")
        .font(.caption2).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
