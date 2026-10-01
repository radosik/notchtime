import SwiftUI
import NotchTimeCore

/// Column widths shared by the header row and every entry row so they line up.
private enum Col {
    static let client: CGFloat = 112
    static let project: CGFloat = 112
    static let date: CGFloat = 104
    static let time: CGFloat = 62
    static let duration: CGFloat = 76
    static let actions: CGFloat = 60
    static let gap: CGFloat = 10
}

struct HistoryView: View {
    @ObservedObject var store: TimeStore
    let export: (Date) -> Void
    let restart: (TimeEntry) -> Void
    @Binding var page: MainPage

    @State private var month: Date = Date()
    @State private var pendingDelete: TimeEntry?

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
                .padding(.top, 16)
                .padding(.bottom, 12)

            columnHeader
                .padding(.horizontal, 22 + 14)
                .padding(.bottom, 6)

            if monthEntries.isEmpty {
                Spacer()
                Text("Nothing tracked in \(Self.monthFormatter.string(from: month)).")
                    .font(Theme.rounded)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(days) { day in
                            DaySection(day: day.day, entries: day.entries, store: store,
                                       onRestart: restart,
                                       onDelete: { pendingDelete = $0 })
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { e in
            Button("Delete \"\(e.title.isEmpty ? "Untitled" : e.title)\"", role: .destructive) {
                store.delete(e.id)
            }
        } message: { e in
            Text(DurationFormat.hms(e.duration(now: store.now)) + " of tracked time will be removed.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PageToggle(page: $page)

            HStack(spacing: 2) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(RoundIconButtonStyle())
            .padding(.leading, 6)

            Text(Self.monthFormatter.string(from: month))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
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

    private var columnHeader: some View {
        HStack(spacing: Col.gap) {
            Text("Task").frame(maxWidth: .infinity, alignment: .leading)
            Text("Client").frame(width: Col.client, alignment: .leading)
            Text("Project").frame(width: Col.project, alignment: .leading)
            Text("Date").frame(width: Col.date, alignment: .leading)
            Text("Start").frame(width: Col.time, alignment: .leading)
            Text("End").frame(width: Col.time, alignment: .leading)
            Text("Duration").frame(width: Col.duration, alignment: .trailing)
            Spacer().frame(width: Col.actions, height: 1)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.textFaint)
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

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, e in
                    if index > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 14)
                    }
                    EntryRowEditor(entry: e, store: store, onRestart: onRestart, onDelete: onDelete)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
        }
    }
}

/// One entry, every field editable in place. Edits are saved as you make them.
struct EntryRowEditor: View {
    let entry: TimeEntry
    @ObservedObject var store: TimeStore
    let onRestart: (TimeEntry) -> Void
    let onDelete: (TimeEntry) -> Void

    private var calendar: Calendar { Calendar.current }

    // MARK: Bindings straight into the store

    private var title: Binding<String> {
        Binding(get: { entry.title },
                set: { v in var e = entry; e.title = v; store.update(e) })
    }

    private var clientID: Binding<UUID?> {
        Binding(get: { entry.clientID },
                set: { id in
                    var e = entry
                    e.clientID = id
                    let projects = store.client(id: id)?.projects ?? []
                    if let p = e.project, !projects.contains(p) { e.project = nil }
                    store.update(e)
                })
    }

    private var project: Binding<String> {
        Binding(get: { entry.project ?? "" },
                set: { v in var e = entry; e.project = v.isEmpty ? nil : v; store.update(e) })
    }

    /// Changing the date moves the whole entry (start and end) to that day, keeping the clock times.
    private var day: Binding<Date> {
        Binding(get: { entry.start },
                set: { newDay in
                    var e = entry
                    let dayStart = calendar.startOfDay(for: newDay)
                    let length = e.end.map { $0.timeIntervalSince(e.start) }
                    e.start = Self.combine(day: dayStart, time: e.start, calendar: calendar)
                    if let length { e.end = e.start.addingTimeInterval(length) }
                    if e.end == nil { e.start = min(e.start, Date()) }
                    store.update(e)
                })
    }

    private var startTime: Binding<Date> {
        Binding(get: { entry.start },
                set: { t in
                    var e = entry
                    let dayStart = calendar.startOfDay(for: e.start)
                    e.start = Self.combine(day: dayStart, time: t, calendar: calendar)
                    if e.end == nil {
                        e.start = min(e.start, Date())
                    } else if let end = e.end, end < e.start {
                        e.end = e.start
                    }
                    store.update(e)
                })
    }

    private var endTime: Binding<Date> {
        Binding(get: { entry.end ?? Date() },
                set: { t in
                    var e = entry
                    let dayStart = calendar.startOfDay(for: e.start)
                    var end = Self.combine(day: dayStart, time: t, calendar: calendar)
                    if end < e.start, let next = calendar.date(byAdding: .day, value: 1, to: end) { end = next }
                    e.end = end
                    store.update(e)
                })
    }

    private static func combine(day: Date, time: Date, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
    }

    private var projects: [String] { store.client(id: entry.clientID)?.projects ?? [] }

    var body: some View {
        HStack(spacing: Col.gap) {
            HStack(spacing: 8) {
                if entry.isRunning {
                    Circle().fill(Theme.tongueTop).frame(width: 6, height: 6)
                        .shadow(color: Theme.tongueTop.opacity(0.9), radius: 4)
                }
                TextField("Untitled", text: title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: clientID) {
                Text("—").tag(UUID?.none)
                ForEach(store.clients) { c in
                    Text(c.name).tag(Optional(c.id))
                }
            }
            .labelsHidden()
            .frame(width: Col.client)

            Picker("", selection: project) {
                Text("—").tag("")
                ForEach(projects, id: \.self) { p in
                    Text(p).tag(p)
                }
            }
            .labelsHidden()
            .disabled(projects.isEmpty)
            .opacity(projects.isEmpty ? 0.35 : 1)
            .frame(width: Col.project)

            DatePicker("", selection: day, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: Col.date)

            DatePicker("", selection: startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: Col.time)

            if entry.isRunning {
                Text("now")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: Col.time, alignment: .leading)
            } else {
                DatePicker("", selection: endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: Col.time)
            }

            Text(DurationFormat.hms(entry.duration(now: store.now)))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: Col.duration, alignment: .trailing)

            HStack(spacing: 4) {
                if entry.isRunning {
                    RowIcon(symbol: "stop.fill", tint: Theme.tongueTop, help: "Stop") { store.stop() }
                } else {
                    RowIcon(symbol: "arrow.counterclockwise", help: "Continue this task") { onRestart(entry) }
                }
                RowIcon(symbol: "trash", help: "Delete") { onDelete(entry) }
            }
            .frame(width: Col.actions, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct RowIcon: View {
    var symbol: String
    var tint: Color = Theme.textDim
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
