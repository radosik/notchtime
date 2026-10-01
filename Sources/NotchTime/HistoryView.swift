import SwiftUI
import NotchTimeCore

struct HistoryView: View {
    @ObservedObject var store: TimeStore
    let export: (Date) -> Void
    let restart: (TimeEntry) -> Void

    @State private var month: Date = Date()
    @State private var editing: TimeEntry?

    private var calendar: Calendar { Calendar.current }
    private var range: DateInterval { calendar.dateInterval(of: .month, for: month)! }

    private var monthEntries: [TimeEntry] {
        store.entries(in: range).sorted { $0.start > $1.start }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [TimeEntry]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        var buckets: [Date: [TimeEntry]] = [:]
        for e in monthEntries {
            buckets[calendar.startOfDay(for: e.start), default: []].append(e)
        }
        return buckets.keys.sorted(by: >).map { DayGroup(day: $0, entries: buckets[$0]!) }
    }

    private var monthTotal: TimeInterval {
        monthEntries.reduce(0) { $0 + $1.duration(now: store.now) }
    }

    private var monthAmount: Double {
        ReportExporter.groups(entries: monthEntries, clients: store.clients, now: store.now)
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            if monthEntries.isEmpty {
                Spacer()
                Text("Nothing tracked in \(Self.monthFormatter.string(from: month)).")
                    .font(Theme.rounded)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(days) { day in
                            DaySection(day: day.day, entries: day.entries, store: store,
                                       onEdit: { editing = $0 },
                                       onRestart: restart,
                                       onDelete: { store.delete($0.id) })
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Theme.surface.ignoresSafeArea())
        .sheet(item: $editing) { entry in
            EntryEditor(store: store, entry: entry)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(RoundIconButtonStyle())

            Text(Self.monthFormatter.string(from: month))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormat.hms(monthTotal))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text(String(format: "$%.2f", monthAmount))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
            }

            Button { export(month) } label: {
                Label("Export .xlsx", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PillowButtonStyle(tint: .cloud, size: 12.5, horizontal: 16, vertical: 8))
        }
    }

    private func shift(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: month) { month = d }
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.textDim)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .contentShape(Circle())
    }
}

struct DaySection: View {
    let day: Date
    let entries: [TimeEntry]
    @ObservedObject var store: TimeStore
    let onEdit: (TimeEntry) -> Void
    let onRestart: (TimeEntry) -> Void
    let onDelete: (TimeEntry) -> Void

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayFormatter.string(from: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(DurationFormat.hms(entries.reduce(0) { $0 + $1.duration(now: store.now) }))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 1) {
                ForEach(entries) { e in
                    EntryRow(entry: e, store: store)
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(e) }
                        .contextMenu {
                            Button("Edit…") { onEdit(e) }
                            if !e.isRunning { Button("Continue timer") { onRestart(e) } }
                            Divider()
                            Button("Delete", role: .destructive) { onDelete(e) }
                        }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
        }
    }
}

struct EntryRow: View {
    let entry: TimeEntry
    @ObservedObject var store: TimeStore

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if entry.isRunning {
                Circle().fill(Theme.tongueTop).frame(width: 6, height: 6)
                    .shadow(color: Theme.tongueTop.opacity(0.9), radius: 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let c = store.client(for: entry) {
                    Chip(text: (entry.project.map { "\(c.name) · \($0)" }) ?? c.name)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(DurationFormat.hms(entry.duration(now: store.now)))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text("\(Self.time.string(from: entry.start)) – \(entry.end.map { Self.time.string(from: $0) } ?? "now")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Editor

struct EntryEditor: View {
    @ObservedObject var store: TimeStore
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry
    @State private var title: String
    @State private var clientID: UUID?
    @State private var project: String
    @State private var day: Date
    @State private var startTime: Date
    @State private var endTime: Date

    init(store: TimeStore, entry: TimeEntry) {
        self.store = store
        self.entry = entry
        _title = State(initialValue: entry.title)
        _clientID = State(initialValue: entry.clientID)
        _project = State(initialValue: entry.project ?? "")
        _day = State(initialValue: entry.start)
        _startTime = State(initialValue: entry.start)
        _endTime = State(initialValue: entry.end ?? Date())
    }

    private var projects: [String] {
        store.client(id: clientID)?.projects ?? []
    }

    private var previewDuration: TimeInterval {
        let (s, e) = composed()
        return max(0, (e ?? Date()).timeIntervalSince(s))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.isRunning ? "Running timer" : "Edit entry")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)

            field("Task") {
                TextField("What were you working on?", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                field("Client") {
                    Picker("", selection: $clientID) {
                        Text("No client").tag(UUID?.none)
                        ForEach(store.clients) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }
                    .labelsHidden()
                }
                field("Project") {
                    Picker("", selection: $project) {
                        Text("No project").tag("")
                        ForEach(projects, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    .labelsHidden()
                    .disabled(projects.isEmpty)
                }
            }
            .onChange(of: clientID) { _, _ in
                if !projects.contains(project) { project = "" }
            }

            HStack(spacing: 12) {
                field("Date") {
                    DatePicker("", selection: $day, displayedComponents: .date)
                        .labelsHidden()
                }
                field("Start") {
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                field(entry.isRunning ? "End (running)" : "End") {
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(entry.isRunning)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Duration")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                    Text(DurationFormat.hms(previewDuration))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
            }

            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(entry.id)
                    dismiss()
                }
                .buttonStyle(PillowButtonStyle(tint: .ghost, size: 12.5, horizontal: 14, vertical: 8))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillowButtonStyle(tint: .ghost, size: 12.5, horizontal: 14, vertical: 8))
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(PillowButtonStyle(tint: .cloud, size: 12.5, horizontal: 18, vertical: 8))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.surface)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textDim)
            content()
        }
    }

    /// Combine the chosen day with the chosen times. Overnight entries roll the end into the next day.
    private func composed() -> (Date, Date?) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        func at(_ t: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: dayStart) ?? dayStart
        }
        let start = at(startTime)
        if entry.isRunning { return (min(start, Date()), nil) }
        var end = at(endTime)
        if end < start, let next = cal.date(byAdding: .day, value: 1, to: end) { end = next }
        return (start, end)
    }

    private func save() {
        var e = entry
        e.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        e.clientID = clientID
        e.project = project.isEmpty ? nil : project
        let (s, end) = composed()
        e.start = s
        e.end = end
        store.update(e)
        dismiss()
    }
}
