import Foundation

/// Response metadata only. Validators stay in memory and never enter diagnostics.
package struct WeatherHTTPMetadata: Equatable, Sendable {
    package struct Validators: Equatable, Sendable {
        package var etag: String?
        package var lastModified: String?
        package init(etag: String? = nil, lastModified: String? = nil) {
            self.etag = etag; self.lastModified = lastModified
        }
        var isEmpty: Bool { etag == nil && lastModified == nil }
        func matches(_ response: Validators) -> Bool {
            if let etag, let other = response.etag {
                let left = etag.hasPrefix("W/") ? etag.dropFirst(2) : etag[...]
                let right = other.hasPrefix("W/") ? other.dropFirst(2) : other[...]
                return left == right
            }
            if let lastModified, let other = response.lastModified { return lastModified == other }
            return !isEmpty
        }
    }

    package struct CacheControl: Equatable, Sendable {
        var maxAge: TimeInterval?
        var noCache = false
        var noStore = false
        var mustRevalidate = false
        var invalid = false
    }

    package enum FreshnessReason: String, Sendable { case maxAge, expires, heuristic, forbidden, invalid }
    package let receivedWall: Date
    package let receivedTick: TimeInterval
    package let duration: TimeInterval
    package var date: Date?
    package var expires: Date?
    package var age: TimeInterval?
    package var control: CacheControl?
    package var validators: Validators
    package var retryDelay: TimeInterval?
    private var datePresent: Bool
    private var expiresPresent: Bool
    private var agePresent: Bool
    private var retryPresent: Bool
    private var invalidHeader: Bool
    private var heuristicLimit: TimeInterval?

    package init(headers: [String: String], receivedWall: Date, receivedTick: TimeInterval,
                 duration: TimeInterval = 0, requestWall: Date? = nil) {
        var fields: [String: String] = [:]
        var duplicates = Set<String>()
        for (name, value) in headers {
            let key = name.lowercased()
            if fields[key] != nil, ["date", "expires", "age", "cache-control", "etag", "last-modified"].contains(key) {
                duplicates.insert(key)
            }
            fields[key] = value
        }
        self.receivedWall = receivedWall
        self.receivedTick = receivedTick
        self.duration = max(0, duration)
        datePresent = fields["date"] != nil
        expiresPresent = fields["expires"] != nil
        agePresent = fields["age"] != nil
        retryPresent = fields["retry-after"] != nil
        date = fields["date"].flatMap { Self.httpDate($0, now: receivedWall) }
        expires = fields["expires"].flatMap { Self.httpDate($0, now: receivedWall) }
        age = fields["age"].flatMap(Self.deltaSeconds)
        control = fields["cache-control"].map(Self.parseControl)
        if duplicates.contains("date") { date = nil }
        if duplicates.contains("expires") { expires = nil }
        if duplicates.contains("age") { age = nil }
        if duplicates.contains("cache-control") { control?.invalid = true }
        invalidHeader = (datePresent && date == nil) || (agePresent && age == nil)
            || date.map { $0.timeIntervalSince(receivedWall) > 60 } == true
            || requestWall.map { abs(receivedWall.timeIntervalSince($0) - max(0, duration)) > 60 } == true
        validators = Validators(etag: Self.entityTag(fields["etag"]), lastModified: Self.modified(fields["last-modified"], now: receivedWall))
        if duplicates.contains("etag") { validators.etag = nil }
        if duplicates.contains("last-modified") { validators.lastModified = nil }
        retryDelay = Self.retryDelay(fields["retry-after"], wall: receivedWall, serverDate: date)
    }

    package var freshnessReason: FreshnessReason {
        if invalidHeader || control?.invalid == true { return .invalid }
        if control?.noStore == true || control?.noCache == true { return .forbidden }
        if control?.maxAge != nil { return .maxAge }
        if expiresPresent && expires == nil { return .invalid }
        if expires != nil { return .expires }
        return .heuristic
    }

    package var ageAtReceipt: TimeInterval {
        max(max(0, date.map { receivedWall.timeIntervalSince($0) } ?? 0), (age ?? 0) + duration)
    }

    package var remaining: TimeInterval {
        switch freshnessReason {
        case .invalid, .forbidden: return 0
        case .maxAge: return max(0, (control?.maxAge ?? 0) - ageAtReceipt)
        case .expires:
            guard let expires else { return 0 }
            if let date { return max(0, expires.timeIntervalSince(date) - ageAtReceipt) }
            return max(0, expires.timeIntervalSince(receivedWall) - (age ?? 0) - duration)
        case .heuristic: return min(max(0, 1_800 - ageAtReceipt), heuristicLimit ?? 1_800)
        }
    }

    package var allowsStorage: Bool { control?.noStore != true }

    static func fromLegacyFields(expires: Date?, lastModified: String?, wall: Date, tick: TimeInterval) -> WeatherHTTPMetadata {
        var metadata = WeatherHTTPMetadata(headers: [:], receivedWall: wall, receivedTick: tick)
        if let expires, expires.timeIntervalSince1970.isFinite {
            metadata.date = wall
            metadata.datePresent = true
            metadata.expires = expires
            metadata.expiresPresent = true
        }
        metadata.validators.lastModified = modified(lastModified, now: wall)
        return metadata
    }

    package func revalidated(by response: WeatherHTTPMetadata) -> WeatherHTTPMetadata {
        var merged = response
        if response.control == nil { merged.control = control }
        if !response.expiresPresent { merged.expires = expires; merged.expiresPresent = expiresPresent }
        if !response.datePresent { merged.date = date; merged.datePresent = datePresent }
        if !response.agePresent && agePresent && age == nil {
            merged.age = nil
            merged.agePresent = true
        } else if !response.agePresent && response.date == nil {
            merged.age = ageAtReceipt + max(0, response.receivedTick - receivedTick)
            merged.agePresent = true
        }
        merged.invalidHeader = response.invalidHeader || (merged.datePresent && merged.date == nil)
            || (merged.agePresent && merged.age == nil)
            || merged.date.map { $0.timeIntervalSince(response.receivedWall) > 60 } == true
        merged.validators.etag = response.validators.etag ?? validators.etag
        merged.validators.lastModified = response.validators.lastModified ?? validators.lastModified
        if merged.freshnessReason == .heuristic {
            merged.heuristicLimit = max(0, remaining - max(0, response.receivedTick - receivedTick))
        }
        return merged
    }

    package var diagnosticFields: String {
        "freshness=\(freshnessReason.rawValue) date=\(datePresent ? (date == nil ? "invalid" : "valid") : "absent") " +
        "age=\(agePresent ? (age == nil ? "invalid" : "valid") : "absent") " +
        "expires=\(expiresPresent ? (expires == nil ? "invalid" : "valid") : "absent") " +
        "cache_control=\(control.map { $0.invalid ? "invalid" : "valid" } ?? "absent") " +
        "etag_present=\(validators.etag != nil) modified_present=\(validators.lastModified != nil) " +
        "retry_after=\(retryPresent ? (retryDelay == nil ? "invalid" : "valid") : "absent") " +
        "age_s=\(Self.bounded(ageAtReceipt)) remaining_s=\(Self.bounded(remaining)) " +
        "date_receipt_s=\(Self.bounded(date?.timeIntervalSince(receivedWall) ?? 0)) " +
        "expires_date_s=\(Self.bounded(expires.flatMap { expiry in date.map { expiry.timeIntervalSince($0) } } ?? 0)) " +
        "expires_receipt_s=\(Self.bounded(expires?.timeIntervalSince(receivedWall) ?? 0))"
    }

    private static func bounded(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(31_536_000, max(-31_536_000, value.rounded(.towardZero))))
    }

    private static func validator(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 1_024,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }

    private static func entityTag(_ value: String?) -> String? {
        guard let value = validator(value) else { return nil }
        let opaque = value.hasPrefix("W/") ? String(value.dropFirst(2)) : value
        guard opaque.count >= 2, opaque.first == "\"", opaque.last == "\"",
              opaque.dropFirst().dropLast().unicodeScalars.allSatisfy({ $0.value > 32 && $0.value != 34 && $0.value != 127 }) else { return nil }
        return value
    }

    private static func modified(_ value: String?, now: Date) -> String? {
        guard let value = validator(value), httpDate(value, now: now) != nil else { return nil }
        return value
    }

    package static func deltaSeconds(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.utf8.count <= 20, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = UInt64(text) else { return nil }
        return Double(value)
    }

    private static func parseControl(_ text: String) -> CacheControl {
        var value = CacheControl()
        guard text.utf8.count <= 4_096 else { value.invalid = true; return value }
        var seen = Set<String>()
        for directive in text.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = directive.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard let name = parts.first, !name.isEmpty else { value.invalid = true; continue }
            if ["max-age", "no-cache", "no-store", "must-revalidate"].contains(name), !seen.insert(name).inserted { value.invalid = true }
            switch name {
            case "max-age":
                if parts.count == 2 {
                    let raw = parts[1]
                    if raw.first == "\"" && raw.last == "\"" && raw.count >= 2 {
                        value.maxAge = deltaSeconds(String(raw.dropFirst().dropLast()))
                    } else { value.maxAge = deltaSeconds(raw) }
                }
                if value.maxAge == nil { value.invalid = true }
            case "no-cache": value.noCache = true
            case "no-store": value.noStore = true
            case "must-revalidate": value.mustRevalidate = true
            default: break
            }
        }
        return value
    }

    package static func httpDate(_ text: String, now: Date = Date()) -> Date? {
        guard text.utf8.count <= 128 else { return nil }
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if var date = formatter.date(from: text) {
                if format.contains("-yy "), date.timeIntervalSince(now) > 50 * 366 * 86_400 {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = formatter.timeZone
                    guard let earlier = calendar.date(byAdding: .year, value: -100, to: date) else { return nil }
                    date = earlier
                }
                return date
            }
        }
        return nil
    }

    package static func retryDelay(_ text: String?, wall: Date, serverDate: Date?) -> TimeInterval? {
        guard let text else { return nil }
        if let delta = deltaSeconds(text) { return delta }
        guard let deadline = httpDate(text, now: wall) else { return nil }
        return max(0, max(deadline.timeIntervalSince(wall), serverDate.map { deadline.timeIntervalSince($0) } ?? 0))
    }
}
