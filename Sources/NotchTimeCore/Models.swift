import Foundation

/// A billable client. A client can have several projects, each of which is reported
/// as its own group in the export.
public struct Client: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var projects: [String]
    public var hourlyRate: Double

    public init(id: UUID = UUID(), name: String, projects: [String] = [], hourlyRate: Double = 0) {
        self.id = id
        self.name = name
        self.projects = projects
        self.hourlyRate = hourlyRate
    }
}

/// One tracked block of time. `end == nil` means the timer is still running.
public struct TimeEntry: Codable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var clientID: UUID?
    public var project: String?
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), title: String, clientID: UUID? = nil, project: String? = nil, start: Date, end: Date? = nil) {
        self.id = id
        self.title = title
        self.clientID = clientID
        self.project = project
        self.start = start
        self.end = end
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

public enum DurationFormat {
    /// "HH:MM:SS", hours may exceed 24 (e.g. "30:32:38") – same as Clockify.
    public static func hms(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// "H:MM" compact form for the island, e.g. "0:42" or "13:15".
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Decimal hours rounded to 2 places (13.26).
    public static func decimalHours(_ seconds: TimeInterval) -> Double {
        (seconds / 3600 * 100).rounded() / 100
    }
}
