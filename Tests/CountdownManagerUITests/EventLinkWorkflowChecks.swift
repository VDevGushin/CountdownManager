import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testEventLinkWorkflows(in directory: URL) async throws {
    let suite = "CountdownLinks.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var opened: [URL] = []
    var succeeds = true
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, loginItemManagementIsAvailable: false,
                      openWebURL: { opened.append($0); return succeeds })
    for _ in 0..<2_000 where store.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!store.isLoading)
    let today = Day(Date())
    let link = EventLink(name: "Маршрут", address: "https://example.com/map")
    let event = Countdown(title: "Поездка", date: today, emoji: "", links: [link])
    let saved = await store.save(event, primary: true)
    precondition(saved)
    var draft = EventEditorDraft(item: store.data.items[0])
    draft.links[0].name = "Changed draft"
    precondition(store.data.items[0].links == [link])
    precondition(EventEditorDraft(item: store.data.items[0]).links == [link])
    precondition(EventEditorDraft(item: nil).links.isEmpty && EventEditorDraft(day: today).links.isEmpty)
    draft.links.append(EventLink())
    precondition(!editorCanSave(title: draft.title, note: draft.note, date: today, emoji: "",
                               links: draft.links, today: today))
    draft.links.removeLast()
    let edited = await store.save(draft.countdown(id: event.id, date: today), primary: true, requireExisting: true)
    precondition(edited)
    let currentLink = store.data.items[0].links[0]
    store.openLink(link, eventID: event.id)
    precondition(opened.isEmpty && store.error != nil)
    store.error = nil
    store.openLink(currentLink, eventID: event.id)
    precondition(opened == [currentLink.url!] && store.error == nil)
    succeeds = false
    store.openLink(currentLink, eventID: event.id)
    precondition(opened.count == 2 && store.error != nil)
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(restored == store.data && restored.items[0].links[0] == currentLink)
    store.error = nil
    store.openLink(currentLink, eventID: UUID())
    precondition(opened.count == 2 && store.error != nil)
    let failing = Store(fileURL: fileURL, disclosureDefaults: defaults,
                        persistenceSaveOverride: { _, _ in throw CocoaError(.fileWriteNoPermission) },
                        loginItemManagementIsAvailable: false, openWebURL: { _ in preconditionFailure("No automatic opens") })
    for _ in 0..<2_000 where failing.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!failing.isLoading)
    let before = try Data(contentsOf: fileURL)
    var changed = EventEditorDraft(item: restored.items[0])
    changed.links[0].address = "https://example.com/new"
    let rejected = await failing.save(changed.countdown(id: event.id, date: today), primary: true, requireExisting: true)
    precondition(!rejected && changed.links[0].address.hasSuffix("/new"))
    let after = try Data(contentsOf: fileURL)
    precondition(before == after)
    try await testRemovedAndExpiredLinkOpening(in: directory.appendingPathComponent("expiry"), defaults: defaults)
    print("PASS links workflows: draft/Cancel/Save/restart, invalid drafts, stale identity, browser rejection, failed write retains disk and draft")
}

@MainActor
private func testRemovedAndExpiredLinkOpening(in directory: URL, defaults: UserDefaults) async throws {
    var clock = Date()
    var opened = 0
    let store = Store(fileURL: directory.appendingPathComponent("countdowns.json"), disclosureDefaults: defaults,
                      now: { clock }, loginItemManagementIsAvailable: false, openWebURL: { _ in opened += 1; return true })
    for _ in 0..<2_000 where store.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!store.isLoading)
    let link = EventLink(address: "https://example.com")
    var event = Countdown(title: "Expiry boundary", date: Day(clock), emoji: "", links: [link])
    let saved = await store.save(event, primary: false)
    precondition(saved)
    event.links = []
    let removed = await store.save(event, primary: false, requireExisting: true)
    precondition(removed)
    store.openLink(link, eventID: event.id)
    precondition(opened == 0 && store.error != nil)
    event.links = [link]
    let restored = await store.save(event, primary: false, requireExisting: true)
    precondition(restored)
    clock = Day.calendar.date(byAdding: .day, value: 1, to: clock)!
    // Cached rendering has not refreshed yet: the open boundary must use the current civil day.
    store.error = nil
    store.openLink(link, eventID: event.id)
    precondition(opened == 0 && store.error != nil)
    print("PASS links opening: removed values and civil-day expiry reject stale clicks before rendering refresh")
}
