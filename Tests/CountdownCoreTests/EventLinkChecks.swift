import CountdownCore
import Foundation

func testEventLinkValidationAndCompatibility() throws {
    let valid = ["https://example.com", "HTTP://localhost:8080/path?q=1#part",
                 "https://example.com/a%20b", "https://пример.рф/путь"]
    for address in valid { precondition(EventLink(address: address).url != nil, address) }
    for address in ["", "example.com", "//example.com", "file:///tmp/a", "javascript:alert(1)",
                    "mailto:a@example.com", "https://", "https://example.com/a b", "https://a\nb.com",
                    "https://user:secret@example.com"] {
        precondition(EventLink(address: address).url == nil, address)
    }
    let today = Day(Date())
    let link = EventLink(name: "  Маршрут  ", address: " \nhttps://example.com/path?q=1#map\t")
    var data = CountdownData()
    let event = Countdown(title: "Поездка", note: "Заметка", date: today, emoji: "",
                          subtasks: [try Subtask(text: "Билет", isCompleted: true)], links: [link])
    try data.save(event, primary: true, today: today)
    precondition(data.items[0].links == [link.normalized()])
    precondition(data.items[0].links[0].id == link.id && data.primaryID == event.id)
    precondition(EventLink(address: "https://example.com/x").displayName == "example.com")
    let bytes = try JSONEncoder().encode(data)
    let decoded = try JSONDecoder().decode(CountdownData.self, from: bytes)
    precondition(decoded == data)
    let prior = data
    var invalid = data.items[0]
    invalid.links.append(EventLink(address: "file:///tmp/a"))
    do {
        try data.save(invalid, primary: false, today: today)
        preconditionFailure("Invalid links must not mutate data")
    } catch EventLinkError.address {}
    precondition(data == prior)
    invalid.links = Array(repeating: link, count: 2)
    do {
        try data.save(invalid, primary: false, today: today)
        preconditionFailure("Duplicate identities must be rejected")
    } catch EventLinkError.duplicateIdentity {}
    invalid.links = (0..<10).map { EventLink(name: "\($0)", address: "https://example.com/\($0)") }
    try data.save(invalid, primary: true, today: today)
    let ten = data
    invalid.links.append(EventLink(address: "https://example.com/11"))
    do {
        try data.save(invalid, primary: false, today: today)
        preconditionFailure("Eleventh link must be rejected")
    } catch EventLinkError.limit {}
    precondition(data == ten)

    let legacy = Countdown(title: "Legacy", date: today, emoji: "")
    let legacyBytes = try JSONEncoder().encode(legacy)
    precondition(!String(decoding: legacyBytes, as: UTF8.self).contains("\"links\""))
    let decodedLegacy = try JSONDecoder().decode(Countdown.self, from: legacyBytes)
    precondition(decodedLegacy.links.isEmpty)
    guard var object = try JSONSerialization.jsonObject(with: legacyBytes) as? [String: Any] else {
        preconditionFailure("Expected an event object")
    }
    for malformed: Any in [NSNull(), "not an array", [["id": UUID().uuidString, "name": "Bad", "address": "file:///tmp/a"]]] {
        object["links"] = malformed
        let malformedBytes = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(Countdown.self, from: malformedBytes)
            preconditionFailure("Malformed link data must not silently become empty")
        } catch {}
    }
    print("PASS links: URL schemes/Unicode/whitespace, normalization, 0/10/11, identities, legacy and malformed JSON")
}

func testEventLinkRepositoryBoundaries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LinkChecks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: url)
    let today = Day(Date())
    var data = CountdownData()
    data.items = [Countdown(title: "Saved", date: today, emoji: "",
                            links: [EventLink(address: "https://example.com")])]
    let wrote = try await repository.save(data, revision: 1)
    precondition(wrote)
    let original = try Data(contentsOf: url)
    var invalid = data
    invalid.items[0].links[0].address = "javascript:bad"
    do {
        _ = try await repository.save(invalid, revision: 2)
        preconditionFailure("Repository must enforce link validation")
    } catch EventLinkError.address {}
    let preserved = try Data(contentsOf: url)
    precondition(preserved == original)
    let restored = try await CountdownRepository(fileURL: url).load()
    precondition(restored == data)
    let stale = try await repository.save(CountdownData(), revision: 0)
    precondition(!stale)
    print("PASS links repository: restart, rejected raw save and stale revision preserve durable data")
}
