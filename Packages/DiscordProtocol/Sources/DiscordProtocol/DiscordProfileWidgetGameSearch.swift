import Foundation

public enum DiscordProfileWidgetGameSearch {
    public static func normalizedQuery(_ query: String) -> String {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: " ")
        return String(decoding: normalized.utf16.prefix(100), as: UTF16.self)
    }

    static func retryAfter(data: Data, response: HTTPURLResponse) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header), seconds.isFinite, seconds >= 1 { return floor(seconds) }
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let seconds = body["retry_after"] as? Double, seconds.isFinite, seconds > 0 { return seconds }
        return 0
    }
}

struct ProfileGameAutocompleteFailure: Sendable {
    let error: any Error
    let expiresAt: Date
}
