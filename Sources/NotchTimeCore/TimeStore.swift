import Foundation
import Combine

/// Everything the app persists. Stored as one JSON file in Application Support.
struct Snapshot: Codable {
    var version: Int = 1
    var reportName: String = ""
    var clients: [Client] = []
    var entries: [TimeEntry] = []
}

/// Single source of truth for entries, clients and the running timer.
/// All access happens on the main thread (UI-driven app).
public final class TimeStore: ObservableObject {
    @Published public private(set) var entries: [TimeEntry] = []
    @Published public private(set) var clients: [Client] = []
    @Published public var reportName: String = "" {
        didSet { if loaded, reportName != oldValue { save() } }
    }
    /// Ticks once per second while a timer is running so views can redraw.
    @Published public private(set) var now: Date = Date()

    public let fileURL: URL
    private var ticker: Timer?
    private var loaded = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? TimeStore.defaultFileURL()
        load()
        loaded = true
        if running != nil { startTicker() }
    }

    // MARK: - Derived

    public var running: TimeEntry? { entries.first { $0.end == nil } }

    public func client(for entry: TimeEntry) -> Client? {
        guard let id = entry.clientID else { return nil }
        return clients.first { $0.id == id }
    }

    public func client(id: UUID?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    public func entries(in interval: DateInterval) -> [TimeEntry] {
        entries.filter { interval.contains($0.start) }
    }

    /// Most recently used (title, client, project) combos for one-tap restart.
    public func recent(limit: Int = 3) -> [TimeEntry] {
        var seen = Set<String>()
        var out: [TimeEntry] = []
        for e in entries.sorted(by: { $0.start > $1.start }) where e.end != nil {
            let key = "\(e.clientID?.uuidString ?? "")|\(e.project ?? "")|\(e.title.lowercased())"
            if seen.insert(key).inserted {
                out.append(e)
                if out.count == limit { break }
            }
        }
        return out
    }

    // MARK: - Timer control

    @discardableResult
    public func start(title: String, clientID: UUID?, project: String?, at date: Date = Date()) -> TimeEntry {
        if running != nil { stop(at: date) }
        let entry = TimeEntry(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                              clientID: clientID, project: project, start: date, end: nil)
        entries.insert(entry, at: 0)
        now = Date()
        startTicker()
        save()
        return entry
    }

    public func stop(at date: Date = Date()) {
        guard let idx = entries.firstIndex(where: { $0.end == nil }) else { return }
        entries[idx].end = max(date, entries[idx].start)
        stopTicker()
        save()
    }

    /// "Count from this time instead" while the timer is running.
    public func setRunningStart(_ date: Date) {
        guard let idx = entries.firstIndex(where: { $0.end == nil }) else { return }
        entries[idx].start = min(date, Date())
        now = Date()
        save()
    }

    public func updateRunning(title: String? = nil, clientID: UUID?? = nil, project: String?? = nil) {
        guard let idx = entries.firstIndex(where: { $0.end == nil }) else { return }
        if let title { entries[idx].title = title }
        if let clientID { entries[idx].clientID = clientID }
        if let project { entries[idx].project = project }
        save()
    }

    // MARK: - Entry CRUD

    public func update(_ entry: TimeEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var e = entry
        if let end = e.end, end < e.start { e.end = e.start }
        entries[idx] = e
        entries.sort { $0.start > $1.start }
        if running == nil { stopTicker() } else { startTicker() }
        save()
    }

    public func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if running == nil { stopTicker() }
        save()
    }

    // MARK: - Clients

    public func addClient(name: String, rate: Double = 0, projects: [String] = []) -> Client {
        let c = Client(name: name, projects: projects, hourlyRate: rate)
        clients.append(c)
        save()
        return c
    }

    public func updateClient(_ client: Client) {
        guard let idx = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[idx] = client
        save()
    }

    public func deleteClient(_ id: UUID) {
        clients.removeAll { $0.id == id }
        for i in entries.indices where entries[i].clientID == id {
            entries[i].clientID = nil
            entries[i].project = nil
        }
        save()
    }

    // MARK: - Ticker

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Persistence

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NotchTime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? decoder.decode(Snapshot.self, from: data) {
            clients = snap.clients
            entries = snap.entries.sorted { $0.start > $1.start }
            reportName = snap.reportName
        } else {
            // First launch: nothing yet. Clients and rates are added in Settings.
            clients = []
            entries = []
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snap = Snapshot(reportName: reportName, clients: clients, entries: entries)
        guard let data = try? encoder.encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
