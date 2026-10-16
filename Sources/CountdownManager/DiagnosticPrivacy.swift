import CountdownCore
import Foundation

package enum DiagnosticPrivacy {
    package static func errorFields(_ error: Error) -> String {
        if error is CancellationError { return "category=cancelled" }
        if error is DecodingError { return "category=decode" }
        if let validation = error as? CountdownError {
            let kind: String
            switch validation {
            case .title: kind = "title"
            case .note: kind = "note"
            case .date: kind = "date"
            case .emoji: kind = "emoji"
            case .eventNotFound: kind = "event_missing"
            case .subtaskNotFound: kind = "subtask_missing"
            case .subtaskText: kind = "subtask_text"
            case .subtaskLength: kind = "subtask_length"
            case .subtaskCount: kind = "subtask_count"
            }
            return "category=validation validation=\(kind)"
        }
        let native = error as NSError
        let category: String
        switch native.domain {
        case NSCocoaErrorDomain: category = "cocoa"
        case NSPOSIXErrorDomain: category = "posix"
        case NSURLErrorDomain: category = "url"
        default: return "category=other"
        }
        return "category=\(category) code=\(native.code)"
    }

    /// Export admits known events and typed fields only. Legacy free-form errors are never copied.
    package static func redactedLog(_ data: Data) -> Data {
        let text = String(decoding: data.prefix(512 * 1_024), as: UTF8.self)
        return Data(text.split(separator: "\n").map { redactedLine(String($0.prefix(4_096))) }.joined(separator: "\n").appending("\n").utf8)
    }

    package static func redactedLine(_ line: String) -> String {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return "legacy.redacted" }
        let timestamp = matches(tokens[0], "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$")
        let index = timestamp ? 1 : 0
        guard tokens.indices.contains(index), events.contains(tokens[index]) else { return "legacy.redacted" }
        var output = timestamp ? [tokens[0], tokens[index]] : [tokens[index]]
        for token in tokens.dropFirst(index + 1) {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count != 2 {
                if verbs.contains(token) { output.append(token) }
                continue
            }
            let key = pair[0], value = pair[1]
            if key == "error", !tokens[index].hasPrefix("weather.") { break }
            if safeField(key, value) { output.append(token) }
            // Old Store errors contain arbitrary descriptions, URLs, paths and embedded newlines.
            else if key == "error" { break }
        }
        return output.joined(separator: " ")
    }

    static func version(_ text: String?) -> String {
        guard let text, matches(text, "^[0-9]{1,6}(\\.[0-9]{1,6}){0,3}$") else { return "unknown" }
        return text
    }

    private static func safeField(_ key: String, _ value: String) -> Bool {
        if numericKeys.contains(key) { return matches(value, "^-?[0-9]{1,19}$") || value == "none" || value == "unknown" }
        if booleanKeys.contains(key) { return value == "true" || value == "false" }
        if key == "event", shellEvents.contains(value) { return true }
        if ["id", "event", "primary", "request", "session"].contains(key) {
            return UUID(uuidString: value) != nil || ["none", "true", "false"].contains(value)
        }
        if enumKeys.contains(key) { return values.contains(value) }
        if key == "version" || key == "build" { return version(value) != "unknown" }
        if key == "duration" { return matches(value, "^[0-9]{1,12}(\\.[0-9]{1,3})?s$") }
        return false
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static let numericKeys: Set<String> = [
        "items", "removed", "count", "revision", "demanded", "usable", "sources", "duration_ms", "bytes", "days",
        "full_days", "temperature_days", "condition_days", "usable_days", "fresh_for_s", "retry_in_s", "delay_s",
        "failed_sources", "fresh_sources", "url_code", "code", "status", "http_status", "value", "minutes", "occlusion",
    ]
    private static let booleanKeys: Set<String> = [
        "enabled", "requested", "expanded", "request_pending", "location_pending", "computation_pending", "reduce_motion",
        "appActive", "visible", "key", "onActiveSpace",
        "prompt",
    ]
    private static let enumKeys: Set<String> = ["source", "phase", "result", "mode", "reason", "cache", "decode", "error", "category", "url_kind", "validation", "intent"]
    private static let shellEvents: Set<String> = [
        "launch-ready", "status-action", "show-begin", "show-after-activate", "show-after-panel", "hide",
        "panel-occlusion-did-change", "application-did-resign-active", "active-space-did-change",
    ]
    private static let verbs: Set<String> = [
        "begin", "success", "failure", "rejected", "superseded", "deferred", "starting", "started", "stopped",
        "finished", "session-finished", "preparing", "aborted", "detected", "recovered", "cancelled-active-work",
    ]
    private static let values: Set<String> = [
        "openMeteo", "metNorway", "wttr", "auto", "manual", "init", "enabled", "location", "demand", "shutdown",
        "launch", "diagnostics", "settled", "success", "failure", "not_modified", "cancelled", "scheduled", "fresh", "expired", "empty",
        "none", "ok", "failed", "skipped", "http", "decode", "invalid_data", "invalid_response", "url", "other", "timeout", "offline", "connection",
        "disabled", "no_eligible_dates", "location_pending", "location_unavailable", "loading", "available", "no_usable_data", "stopped",
        "idle", "running", "finished", "cocoa", "posix", "validation", "title", "note", "date", "emoji", "event_missing", "subtask_missing",
        "subtask_text", "subtask_length", "subtask_count", "normalize", "countdown.save", "countdown.primary", "countdown.delete",
        "subtask.add", "subtask.edit", "subtask.delete", "subtask.toggle", "manual-check", "manual-update", "scheduled-update", "sparkle-modal", "deferred-install", "deferred-modal",
        "show", "hide", "ui-smoke", "status-action", "update-ui", "command-w", "window-close", "panel-occluded", "application-deactivation", "active-space-change",
        "permission_required", "denied", "unavailable", "requested",
    ]
    private static let events: Set<String> = [
        "app.launch", "app.terminate", "data.load", "data.save", "data.normalize", "countdown.save", "countdown.primary", "countdown.delete",
        "subtask.disclosure", "subtask.add", "subtask.edit", "subtask.delete", "subtask.toggle", "login-item.change", "login-item.status",
        "diagnostics.open-folder", "diagnostics.export", "diagnostics.dropped", "diagnostics.write", "legacy.redacted",
        "weather.request.start", "weather.request.end", "weather.source", "weather.publication", "weather.computation", "weather.schedule",
        "weather.state", "weather.location", "weather.snapshot", "updates.start", "updates.install", "updates.ui", "updates.termination", "updates.check",
        "timer.invalid-deadline-cleared", "timer.start", "timer.delete", "timer.finished", "timer.completion-alert", "timer.running-pulse", "timer.status-attention",
        "editor.open", "editor.cancel", "ui.stall", "shell.lifecycle",
    ]
}
