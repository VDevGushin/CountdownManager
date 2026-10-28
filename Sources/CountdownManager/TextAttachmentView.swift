import CountdownCore
import SwiftUI

struct TextAttachmentRequest: Identifiable, Equatable {
    let id = UUID()
    let eventID: UUID
    let text: String
}

struct TextAttachmentComposer: View {
    let eventTitle: String
    let submit: (TextAttachment) async -> Bool
    let cancel: () -> Void
    @State private var draft: TextAttachment
    @State private var saving = false
    @State private var failure: String?
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, eventTitle: String, submit: @escaping (TextAttachment) async -> Bool,
         cancel: @escaping () -> Void) {
        self.eventTitle = eventTitle; self.submit = submit; self.cancel = cancel
        _draft = State(initialValue: TextAttachment(text: text))
    }

    private var validationMessage: String? {
        do { try draft.validate(); return nil }
        catch { return error.localizedDescription }
    }
    private var valid: Bool { validationMessage == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Текстовое вложение")
                .font(.custom("Georgia", size: 21))
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                .padding(.horizontal, 16)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("В «\(eventTitle)»").font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Имя файла").font(.system(size: 12))
                TextField("Имя файла", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("materials.text.name")
                    .uiSmokeControl(id: "materials.text.name", value: { draft.name })
                Text("Текст").font(.system(size: 12))
                TextEditor(text: $draft.text)
                    .font(.system(size: 13))
                    .accessibilityLabel("Текст вложения")
                    .accessibilityIdentifier("materials.text.content")
                    .uiSmokeControl(id: "materials.text.content", value: { draft.text })
                Text("Обычный текст .txt · абзацы и переносы сохранятся.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let validationMessage {
                    Text(validationMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("materials.text.validation")
                }
                if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red) }
            }
            .padding(16)
            .disabled(saving)
            Divider()
            HStack(spacing: 9) {
                Spacer(minLength: 0)
                Button("Отмена", action: cancel)
                    .auroraSecondaryAction()
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                    .accessibilityIdentifier("materials.text.cancel")
                    .uiSmokeControl(id: "materials.text.cancel", action: cancel)
                Button(action: create) {
                    if saving { ProgressView().controlSize(.small) }
                    else { Text("Создать вложение") }
                }
                    .auroraPrimaryAction()
                    .disabled(saving || !valid)
                    .accessibilityIdentifier("materials.text.create")
                    .uiSmokeControl(id: "materials.text.create", action: create)
            }
            .controlSize(.regular)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .frame(height: 58)
        }
        .background(AuroraPanelCanvas())
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .accessibilityIdentifier("materials.text.composer")
        .uiSmokeControl(id: "materials.text.composer")
    }

    private func create() {
        guard valid, !saving else { return }
        saving = true
        failure = nil
        Task { @MainActor in
            let saved = await submit(draft)
            saving = false
            if !saved { failure = "Не удалось добавить вложение. Текст сохранён здесь — повторите попытку." }
        }
    }
}
