import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testAttachmentPreviewSessions(in directory: URL) async throws {
    let fixture = try PreviewSessionFixture(directory: directory)
    try await testPreviewLateResolution(fixture: fixture)
    await testPreviewDismissalEffects(fixture: fixture)
    try await testPreviewOriginsAndIndependentSurfaces(fixture: fixture)
    try await testPreviewExternalOpenGuards(fixture: fixture)
    for seed: UInt64 in [0x10, 0xCAFE, 0xBAD5EED, 0xFFFF] {
        try await testPreviewCommandSequence(fixture: fixture, seed: seed)
    }
    try fixture.requireUnchangedFiles()
    print("PASS attachment preview: late/cancelled/same-ID resolution, missing copy, independent surfaces, owner/current-file removal and four seeded 180-command identity sequences")
}

/// Intentionally ignores cancellation so a closed or replaced request can finish late.
@MainActor
private final class PreviewResolutionGate {
    private(set) var requests: [(attachmentID: UUID, eventID: UUID)] = []
    private(set) var completed: Set<Int> = []
    private var pending: [Int: CheckedContinuation<URL?, Never>] = [:]

    func resolve(_ attachment: EventAttachment, eventID: UUID) async -> URL? {
        let index = requests.count
        requests.append((attachment.id, eventID))
        let result = await withCheckedContinuation { pending[index] = $0 }
        completed.insert(index)
        return result
    }

    func finish(_ index: Int, with url: URL?) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("A resolver request must finish exactly once")
        }
        continuation.resume(returning: url)
    }
}

@MainActor
private func testPreviewLateResolution(fixture: PreviewSessionFixture) async throws {
    let event = fixture.events[0]
    let first = event.attachments[0]
    let second = event.attachments[1]
    let gate = PreviewResolutionGate()
    let session = AttachmentPreviewSession()
    let resolver: @MainActor (EventAttachment, UUID) async -> URL? = { attachment, eventID in
        await gate.resolve(attachment, eventID: eventID)
    }
    session.open(event: event, attachmentID: first.id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("first URL resolver starts") { gate.requests.count == 1 }
    precondition(session.isResolving && session.url == nil)
    session.open(event: event, attachmentID: second.id, origin: .library, resolveURL: resolver)
    await requirePreviewEventually("replacement URL resolver starts") { gate.requests.count == 2 }
    gate.finish(1, with: fixture.url(for: second))
    await requirePreviewEventually("replacement URL becomes current") {
        !session.isResolving && session.url == fixture.url(for: second)
    }
    gate.finish(0, with: fixture.url(for: first))
    await requirePreviewEventually("superseded first resolver returns") { gate.completed.contains(0) }
    requirePreviewSelection(session, eventID: event.id, attachmentID: second.id, origin: .library)
    precondition(session.url == fixture.url(for: second), "Late A must never replace B's content")

    session.open(event: event, attachmentID: first.id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("request before close starts") { gate.requests.count == 3 }
    session.close()
    session.close()
    precondition(session.selection == nil && session.url == nil && !session.isResolving)
    session.open(event: event, attachmentID: first.id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("same-ID reopen starts a distinct request") { gate.requests.count == 4 }
    gate.finish(2, with: fixture.url(for: second))
    await requirePreviewEventually("cancelled same-ID generation returns") { gate.completed.contains(2) }
    precondition(session.isResolving && session.url == nil,
                 "A previous generation of the same attachment cannot finish the reopened request")
    gate.finish(3, with: nil)
    await requirePreviewEventually("missing copy ends resolving without losing its identity") { !session.isResolving }
    requirePreviewSelection(session, eventID: event.id, attachmentID: first.id, origin: .summary)
    precondition(session.url == nil, "A missing copy needs an identifiable fallback, not another file")

    session.move(by: 1, in: event, resolveURL: resolver)
    await requirePreviewEventually("navigation recovers after a missing copy") { gate.requests.count == 5 }
    gate.finish(4, with: fixture.url(for: second))
    await requirePreviewEventually("next valid copy becomes current") { !session.isResolving }
    requirePreviewSelection(session, eventID: event.id, attachmentID: second.id, origin: .summary)
    precondition(session.url == fixture.url(for: second))
    session.open(event: event, attachmentID: first.id, origin: .library, resolveURL: resolver)
    await requirePreviewEventually("non-file URL request starts") { gate.requests.count == 6 }
    gate.finish(5, with: URL(string: "https://example.invalid/private-file")!)
    await requirePreviewEventually("non-file URL is rejected") { !session.isResolving }
    precondition(session.url == nil, "A local attachment preview must never navigate to a remote URL")
    session.close()
}

@MainActor
private func testPreviewExternalOpenGuards(fixture: PreviewSessionFixture) async throws {
    let session = AttachmentPreviewSession()
    let event = fixture.events[0]
    let first = event.attachments[0]
    let second = event.attachments[1]
    let gate = PreviewResolutionGate()
    let externalGate = PreviewResolutionGate()
    let resolver: AttachmentPreviewSession.URLResolver = { attachment, eventID in
        await gate.resolve(attachment, eventID: eventID)
    }
    let external: @MainActor (EventAttachment, UUID) async -> Void = { attachment, eventID in
        _ = await externalGate.resolve(attachment, eventID: eventID)
    }
    session.open(event: event, attachmentID: first.id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("external guard resolver starts") { gate.requests.count == 1 }
    session.openExternally(in: event, action: external)
    precondition(!session.isOpeningExternally && externalGate.requests.isEmpty,
                 "Opening externally is unavailable while the copy is still resolving")
    gate.finish(0, with: fixture.url(for: first))
    await requirePreviewEventually("external action becomes available") { !session.isResolving }
    session.openExternally(in: fixture.events[1], action: external)
    precondition(!session.isOpeningExternally, "A foreign event cannot open the selected copy")
    session.openExternally(in: event, action: external)
    session.openExternally(in: event, action: external)
    await requirePreviewEventually("one external action starts despite a double click") { externalGate.requests.count == 1 }
    precondition(session.isOpeningExternally)
    session.open(event: event, attachmentID: second.id, origin: .library, resolveURL: resolver)
    await requirePreviewEventually("replacement invalidates previous external action") { gate.requests.count == 2 }
    gate.finish(1, with: fixture.url(for: second))
    await requirePreviewEventually("replacement resolves") { !session.isResolving }
    session.openExternally(in: event, action: external)
    await requirePreviewEventually("replacement external action starts") { externalGate.requests.count == 2 }
    externalGate.finish(0, with: nil)
    await requirePreviewEventually("old external action finishes late") { externalGate.completed.contains(0) }
    precondition(session.isOpeningExternally,
                 "An old external completion must not unlock a newer file's action")
    precondition(externalGate.requests.map(\.attachmentID) == [first.id, second.id])
    externalGate.finish(1, with: nil)
    await requirePreviewEventually("current external action unlocks after completion") { !session.isOpeningExternally }
    session.close()
    session.openExternally(in: event, action: external)
    precondition(!session.isOpeningExternally && externalGate.requests.count == 2,
                 "A closed preview cannot launch a stale external action")
}

@MainActor
private func testPreviewDismissalEffects(fixture: PreviewSessionFixture) async {
    let session = AttachmentPreviewSession()
    let gate = PreviewResolutionGate()
    let event = fixture.events[0]
    let resolver: AttachmentPreviewSession.URLResolver = { file, eventID in await gate.resolve(file, eventID: eventID) }
    session.open(event: event, attachmentID: event.attachments[0].id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("closing-animation fixture resolver starts") { gate.requests.count == 1 }
    gate.finish(0, with: fixture.url(for: event.attachments[0]))
    await requirePreviewEventually("closing-animation fixture resolves") { !session.isResolving }
    let selection = session.selection
    let url = session.url
    session.cancelPendingEffects()
    precondition(session.selection == selection && session.url == url && !session.isResolving,
                 "Native dismissal must retain already-visible content until final close")
    session.open(event: event, attachmentID: event.attachments[1].id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("pending close request starts") { gate.requests.count == 2 }
    session.cancelPendingEffects()
    precondition(session.isResolving && session.url == nil,
                 "Native dismissal must freeze the resolving presentation rather than flash a missing-copy state")
    gate.finish(1, with: fixture.url(for: event.attachments[1]))
    await requirePreviewEventually("pending request returns after dismissal began") { gate.completed.contains(1) }
    precondition(session.selection?.attachmentID == event.attachments[1].id && session.url == nil && session.isResolving,
                 "A pending completion cannot replace the frozen resolving presentation during native dismissal")
    session.close()
    precondition(session.selection == nil && session.url == nil && !session.isResolving)
}

@MainActor
private func testPreviewOriginsAndIndependentSurfaces(fixture: PreviewSessionFixture) async throws {
    let first = fixture.events[0]
    let other = fixture.events[1]
    let desktop = AttachmentPreviewSession()
    let mini = AttachmentPreviewSession()
    let resolver: @MainActor (EventAttachment, UUID) async -> URL? = { file, _ in fixture.url(for: file) }
    desktop.open(event: first, attachmentID: first.attachments[14].id, origin: .library, resolveURL: resolver)
    mini.open(event: other, attachmentID: other.attachments[0].id, origin: .summary, resolveURL: resolver)
    await requirePreviewEventually("both surface URL requests settle") { !desktop.isResolving && !mini.isResolving }
    desktop.move(by: 1, in: first, resolveURL: resolver)
    await requirePreviewEventually("legacy sixteenth file is reachable") { !desktop.isResolving }
    requirePreviewSelection(desktop, eventID: first.id, attachmentID: first.attachments[15].id, origin: .library)
    requirePreviewSelection(mini, eventID: other.id, attachmentID: other.attachments[0].id, origin: .summary)
    var reduced = first
    reduced.attachments.remove(at: 0)
    desktop.reconcile(event: reduced)
    requirePreviewSelection(desktop, eventID: first.id, attachmentID: first.attachments[15].id, origin: .library)
    reduced.attachments.removeAll { $0.id == first.attachments[15].id }
    desktop.reconcile(event: reduced)
    precondition(desktop.selection == nil && desktop.url == nil && !desktop.isResolving,
                 "Removing the current file closes its preview rather than showing an adjacent file")
    requirePreviewSelection(mini, eventID: other.id, attachmentID: other.attachments[0].id, origin: .summary)
    mini.reconcile(event: nil)
    precondition(mini.selection == nil && mini.url == nil && !mini.isResolving,
                 "An absent or expired owner must release the preview")
}

@MainActor
private func testPreviewCommandSequence(fixture: PreviewSessionFixture, seed: UInt64) async throws {
    let session = AttachmentPreviewSession()
    var generator = PreviewCommandGenerator(state: seed)
    var events = fixture.events
    var expected: (eventID: UUID, attachmentID: UUID, origin: AttachmentPreviewOrigin)?
    let resolver: @MainActor (EventAttachment, UUID) async -> URL? = { file, _ in fixture.url(for: file) }
    for step in 0..<180 {
        let eventIndex = Int(generator.next() % UInt64(events.count))
        let command = Int(generator.next() % 8)
        switch command {
        case 0, 1:
            let event = events[eventIndex]
            if !event.attachments.isEmpty {
                let file = event.attachments[Int(generator.next() % UInt64(event.attachments.count))]
                let origin: AttachmentPreviewOrigin = command == 0 ? .summary : .library
                session.open(event: event, attachmentID: file.id, origin: origin, resolveURL: resolver)
                expected = (event.id, file.id, origin)
            }
        case 2, 3:
            let event = events[eventIndex]
            let direction = command == 2 ? -1 : 1
            if let current = expected, current.eventID == event.id,
               let index = event.attachments.firstIndex(where: { $0.id == current.attachmentID }) {
                let destination = index + direction
                if event.attachments.indices.contains(destination) {
                    expected = (event.id, event.attachments[destination].id, current.origin)
                }
            }
            session.move(by: direction, in: event, resolveURL: resolver)
        case 4:
            session.close()
            expected = nil
        case 5:
            if let current = expected, let index = events.firstIndex(where: { $0.id == current.eventID }) {
                events[index].attachments.removeAll { $0.id == current.attachmentID }
                session.reconcile(event: events[index])
                expected = nil
            }
        case 6:
            session.reconcile(event: nil)
            expected = nil
        default:
            // A stale or foreign file command cannot redirect a valid preview.
            session.open(event: events[eventIndex], attachmentID: fixture.foreignID,
                         origin: .summary, resolveURL: resolver)
        }
        await requirePreviewEventually("seed \(seed), step \(step), command \(command) resolves") { !session.isResolving }
        if let expected {
            requirePreviewSelection(session, eventID: expected.eventID,
                                    attachmentID: expected.attachmentID, origin: expected.origin)
            let owner = events.first { $0.id == expected.eventID }
            let file = owner?.attachments.first { $0.id == expected.attachmentID }
            precondition(file != nil, "The independent command oracle must reference a current saved identity")
            precondition(session.url == file.map { fixture.url(for: $0) },
                         "seed \(seed), step \(step) displayed a different file's URL")
        } else {
            precondition(session.selection == nil && session.url == nil,
                         "seed \(seed), step \(step) resurrected a closed preview")
        }
    }
    session.close()
}

private struct PreviewCommandGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 16
    }
}

@MainActor
private func requirePreviewEventually(_ label: String, _ predicate: () -> Bool) async {
    let deadline = Date().addingTimeInterval(3)
    while !predicate(), Date() < deadline { await Task.yield() }
    precondition(predicate(), label)
}

@MainActor
private func requirePreviewSelection(_ session: AttachmentPreviewSession, eventID: UUID,
                                     attachmentID: UUID, origin: AttachmentPreviewOrigin) {
    precondition(session.selection?.eventID == eventID && session.selection?.attachmentID == attachmentID
                 && session.selection?.origin == origin, "Preview identity and its return route must agree")
}

private struct PreviewSessionFixture {
    let directory: URL
    let events: [Countdown]
    let foreignID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    private let originalFiles: [URL: Data]

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL: Data] = [:]
        events = try [17, 6].enumerated().map { eventIndex, count in
            let attachments = try (0..<count).map { index in
                let identifier = UUID(uuidString: String(format: "77777777-7777-7777-%04d-%012d", eventIndex, index))!
                let bytes = Data("Preview identity \(eventIndex)/\(index)".utf8)
                let attachment = try EventAttachment(id: identifier, name: "Повторяющееся имя.txt", byteCount: Int64(bytes.count))
                let folder = directory.appendingPathComponent(identifier.uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(attachment.name)
                try bytes.write(to: url)
                files[url] = bytes
                return attachment
            }
            return Countdown(title: "Preview event \(eventIndex)", date: Day(Date()), emoji: "", attachments: attachments)
        }
        let snapshot = try JSONEncoder().encode(events)
        let eventURL = directory.appendingPathComponent("events.json")
        try snapshot.write(to: eventURL)
        files[eventURL] = snapshot
        originalFiles = files
    }

    func url(for attachment: EventAttachment) -> URL {
        directory.appendingPathComponent(attachment.id.uuidString).appendingPathComponent(attachment.name)
    }

    func requireUnchangedFiles() throws {
        for (url, bytes) in originalFiles {
            let after = try Data(contentsOf: url)
            precondition(after == bytes, "Preview commands must not mutate event or attachment bytes")
        }
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
        let actualURLs = try enumerator.compactMap { $0 as? URL }.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
        // FileEnumerator and appendingPathComponent can represent the same file with different base URLs.
        let actual = Set(actualURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        let expected = Set(originalFiles.keys.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        precondition(actual == expected,
                     "Read-only preview changed file inventory; added=\(actual.subtracting(expected).sorted()), removed=\(expected.subtracting(actual).sorted())")
    }
}
