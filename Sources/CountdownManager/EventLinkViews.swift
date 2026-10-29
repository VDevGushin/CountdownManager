import CountdownCore
import SwiftUI

/// Shared header for saved material sections; compact disclosures keep their own interaction.
struct SavedMaterialHeading: View {
    let title: String
    let count: Int
    let symbolName: String
    let controlPrefix: String
    let eventID: UUID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                .uiSmokeControl(id: "\(controlPrefix).heading.\(eventID)")
            Spacer()
            Label(String(count), systemImage: symbolName)
                .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.details.\(symbolName).\(eventID)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .accessibilityLabel("\(title): \(count)")
                .uiSmokeControl(id: "\(controlPrefix).count.\(eventID)", value: { String(count) })
        }
    }
}

struct SavedLinkSection: View {
    let item: Countdown
    let surface: String
    let open: (EventLink) -> Void
    @State private var expanded = false
    private var compact: Bool { surface == "panel" }
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings

    var body: some View {
        if !item.links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
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
                            Text(String(item.links.count)).font(.system(size: 11))
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                                .uiSmokeControl(id: "panel.links.count.\(item.id)", value: { String(item.links.count) })
                        }
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ссылки: \(item.links.count), \(expanded ? "свернуть" : "раскрыть")")
                    .accessibilityIdentifier("panel.links.toggle.\(item.id)")
                    .uiSmokeControl(id: "panel.links.toggle.\(item.id)", action: { expanded.toggle() },
                                    value: { expanded ? "expanded" : "collapsed" })
                } else {
                    SavedMaterialHeading(title: "Ссылки", count: item.links.count, symbolName: "link",
                                         controlPrefix: "desktop.links", eventID: item.id)
                }
                if !compact || expanded {
                    linkRows
                }
            }
            .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
            .uiSmokeControl(id: "\(surface).links.\(item.id)", value: { String(item.links.count) })
        }
    }

    private var heading: some View {
        Text("Ссылки")
            .font(.system(size: 12, weight: .semibold))
            .uiSmokeControl(id: "\(surface).links.heading.\(item.id)")
    }

    private var linkRows: some View {
        ForEach(item.links) { link in
            Button { open(link) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.displayName).font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(link.domain).font(.system(size: 11))
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AuroraInstrument.accentInk(
                for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
            .help(link.address)
            .accessibilityLabel("Открыть ссылку: \(link.displayName), \(link.domain)")
            .accessibilityIdentifier("\(surface).links.open.\(link.id)")
            .uiSmokeControl(id: "\(surface).links.open.\(link.id)", action: { open(link) },
                            value: { link.displayName })
        }
    }
}

struct EditorLinkSection: View {
    @Binding var links: [EventLink]
    @State private var touched: Set<UUID> = []
    @FocusState private var focused: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field: Hashable {
        case name(UUID), address(UUID)
        var id: UUID {
            switch self { case let .name(id), let .address(id): id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ссылки").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(links.count)/\(EventLink.maximumCount)").font(.caption2)
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            ForEach($links) { $link in
                linkRow($link)
            }
            Button("Добавить ссылку", action: add)
                .accessibilityIdentifier("editor.links.add")
                .uiSmokeControl(id: "editor.links.add", action: add)
                .disabled(links.count >= EventLink.maximumCount)
            Text(links.count >= EventLink.maximumCount
                 ? "Добавлено 10 ссылок. Уберите одну, чтобы добавить другую."
                 : "Название необязательно. Адрес начинается с https:// или http://.")
                .font(.caption2)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: focused) { [focused] newValue in
            if let previous = focused, previous != newValue { touched.insert(previous.id) }
            if UISmokeConfiguration.wasRequested, let newValue {
                let kind: String
                switch newValue { case .name: kind = "name"; case .address: kind = "address" }
                UISmokeControlRegistry.shared.markFocused("editor.links.\(kind).\(newValue.id)")
            }
        }
        .uiSmokeControl(id: "editor.links", value: { String(links.count) })
    }

    private func linkRow(_ binding: Binding<EventLink>) -> some View {
        let link = binding.wrappedValue
        let invalid = link.url == nil && touched.contains(link.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Ссылка \((links.firstIndex(where: { $0.id == link.id }) ?? 0) + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Spacer()
                Button { remove(link.id) } label: {
                    Image(systemName: "trash").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить ссылку: \(link.displayName.isEmpty ? "без адреса" : link.displayName)")
                .accessibilityIdentifier("editor.links.remove.\(link.id)")
                .uiSmokeControl(id: "editor.links.remove.\(link.id)", action: { remove(link.id) })
            }
            Text("Название · необязательно").font(.caption)
            TextField("Например, маршрут до отеля", text: binding.name)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .name(link.id))
                .accessibilityLabel("Название ссылки")
                .accessibilityIdentifier("editor.links.name.\(link.id)")
                .uiSmokeControl(id: "editor.links.name.\(link.id)", action: { focused = .name(link.id) }, value: { binding.wrappedValue.name })
            Text("Адрес").font(.caption)
            TextField("https://example.com", text: binding.address)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .address(link.id))
                .accessibilityLabel("Адрес ссылки")
                .accessibilityIdentifier("editor.links.address.\(link.id)")
                .uiSmokeControl(id: "editor.links.address.\(link.id)", action: { focused = .address(link.id) }, value: { binding.wrappedValue.address })
            if invalid {
                Text(EventLinkError.address.localizedDescription)
                    .font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("editor.links.error.\(link.id)")
                    .uiSmokeControl(id: "editor.links.error.\(link.id)")
            }
            Divider().padding(.top, 5)
        }
        .id(link.id)
    }

    private func add() {
        guard links.count < EventLink.maximumCount else { return }
        let link = EventLink()
        links.append(link)
        focused = .address(link.id)
    }

    private func remove(_ id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        if focused?.id == id {
            focused = links.indices.contains(index + 1) ? .address(links[index + 1].id)
                : (index > 0 ? .address(links[index - 1].id) : nil)
        }
        links.remove(at: index)
        touched.remove(id)
    }
}
