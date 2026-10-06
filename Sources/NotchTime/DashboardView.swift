import SwiftUI
import Charts
import NotchTimeCore

enum MainPage: String, CaseIterable, Identifiable {
    case history = "History"
    case dashboard = "Dashboard"
    var id: String { rawValue }
}

/// The main window: History ⇄ Dashboard.
struct MainView: View {
    @ObservedObject var store: TimeStore
    let export: (Date) -> Void
    let restart: (TimeEntry) -> Void
    @State private var page: MainPage = .history

    var body: some View {
        Group {
            switch page {
            case .history:
                HistoryView(store: store, export: export, restart: restart, page: $page)
            case .dashboard:
                DashboardView(store: store, page: $page)
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .background(Theme.surface.ignoresSafeArea())
    }
}

/// Two-chip switch shown at the leading edge of each page's header.
struct PageToggle: View {
    @Binding var page: MainPage

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainPage.allCases) { p in
                Button { page = p } label: {
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(page == p ? Theme.ink : Theme.textDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(page == p
                                           ? LinearGradient(colors: [Theme.cloudTop, Theme.cloudBottom], startPoint: .top, endPoint: .bottom)
                                           : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Dashboard

enum Period: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case lastWeek = "Last week"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case last30 = "Last 30 days"
    case custom = "Custom range"
    var id: String { rawValue }
    var steppable: Bool { self != .custom }
}

struct DashboardView: View {
    @ObservedObject var store: TimeStore
    @Binding var page: MainPage

    @State private var period: Period = .thisMonth
    @State private var offset = 0
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    private var calendar: Calendar { Calendar.current }

    // MARK: Period

    private var range: DateInterval {
        let now = Date()
        switch period {
        case .thisWeek, .lastWeek:
            let shift = (period == .lastWeek ? -1 : 0) + offset
            let base = calendar.date(byAdding: .weekOfYear, value: shift, to: now) ?? now
            return calendar.dateInterval(of: .weekOfYear, for: base) ?? DateInterval(start: now, duration: 0)
        case .thisMonth, .lastMonth:
            let shift = (period == .lastMonth ? -1 : 0) + offset
            let base = calendar.date(byAdding: .month, value: shift, to: now) ?? now
            return calendar.dateInterval(of: .month, for: base) ?? DateInterval(start: now, duration: 0)
        case .last30:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: offset * 30, to: tomorrow) ?? tomorrow
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .custom:
            let s = calendar.startOfDay(for: customStart)
            let e = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
            return DateInterval(start: min(s, e), end: max(s, e))
        }
    }

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
    private static let shortDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private var rangeLabel: String {
        let last = range.end.addingTimeInterval(-1)
        return "\(Self.shortDay.string(from: range.start)) – \(Self.shortDayYear.string(from: last))"
    }

    private var dayCount: Int {
        max(1, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
    }

    // MARK: Data

    private var entries: [TimeEntry] { store.entries(in: range) }

    private static let noClient = "No client"

    private func clientName(_ e: TimeEntry) -> String {
        store.client(for: e)?.name ?? Self.noClient
    }

    /// ReportExporter labels client-less work "(No client)"; use the same label as the charts.
    private func normalized(_ groupClientName: String) -> String {
        groupClientName == "(No client)" ? Self.noClient : groupClientName
    }

    private var clientNames: [String] {
        var seen: [String: TimeInterval] = [:]
        for e in entries { seen[clientName(e), default: 0] += e.duration(now: store.now) }
        return seen.sorted { $0.value > $1.value }.map(\.key)
    }

    private static let palette: [Color] = [
        Color(hex: 0xF4F5F7), Theme.tongueTop, Color(hex: 0x6EA8FF),
        Color(hex: 0xFFC46E), Color(hex: 0x7EDBA3), Color(hex: 0xB48CFF), Color(hex: 0x8C9199)
    ]

    private func color(for client: String) -> Color {
        guard let i = clientNames.firstIndex(of: client) else { return Theme.textDim }
        return Self.palette[i % Self.palette.count]
    }

    private struct DayBar: Identifiable {
        let day: Date
        let client: String
        let hours: Double
        var id: String { "\(day.timeIntervalSince1970)|\(client)" }
    }

    private var dayBars: [DayBar] {
        var acc: [Date: [String: TimeInterval]] = [:]
        for e in entries {
            let day = calendar.startOfDay(for: e.start)
            acc[day, default: [:]][clientName(e), default: 0] += e.duration(now: store.now)
        }
        var out: [DayBar] = []
        for (day, byClient) in acc {
            for (client, secs) in byClient {
                out.append(DayBar(day: day, client: client, hours: secs / 3600))
            }
        }
        return out.sorted { $0.day < $1.day }
    }

    private struct Slice: Identifiable {
        let client: String
        let seconds: TimeInterval
        let amount: Double
        var id: String { client }
    }

    private var slices: [Slice] {
        let groups = ReportExporter.groups(entries: entries, clients: store.clients, now: store.now)
        var byClient: [String: (TimeInterval, Double)] = [:]
        for g in groups {
            let name = normalized(g.clientName)
            let cur = byClient[name] ?? (0, 0)
            byClient[name] = (cur.0 + g.seconds, cur.1 + (g.amount ?? 0))
        }
        return byClient.map { Slice(client: $0.key, seconds: $0.value.0, amount: $0.value.1) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var totalSeconds: TimeInterval { entries.reduce(0) { $0 + $1.duration(now: store.now) } }
    private var totalAmount: Double { slices.reduce(0) { $0 + $1.amount } }

    private struct Activity: Identifiable {
        let title: String
        let client: String
        let project: String?
        let seconds: TimeInterval
        var id: String { "\(client)|\(project ?? "")|\(title)" }
    }

    private var activities: [Activity] {
        ReportExporter.groups(entries: entries, clients: store.clients, now: store.now)
            .flatMap { g in g.lines.map { Activity(title: $0.title, client: normalized(g.clientName), project: g.project, seconds: $0.seconds) } }
            .sorted { $0.seconds > $1.seconds }
    }

    private var busiestDay: (Date, TimeInterval)? {
        var acc: [Date: TimeInterval] = [:]
        for e in entries { acc[calendar.startOfDay(for: e.start), default: 0] += e.duration(now: store.now) }
        return acc.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 14) {
                    tiles
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            cardTitle("Hours per day")
                            if entries.isEmpty {
                                emptyNote
                            } else {
                                barChart.frame(height: 244)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                cardTitle("Time by client")
                                if entries.isEmpty { emptyNote } else { donut }
                            }
                        }
                        .frame(width: 360)
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                cardTitle("Most tracked")
                                if entries.isEmpty { emptyNote } else { activityList }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PageToggle(page: $page)

            Spacer()

            if period == .custom {
                HStack(spacing: 6) {
                    DatePicker("", selection: $customStart, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).frame(width: 104)
                    Text("–").foregroundStyle(Theme.textDim)
                    DatePicker("", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).frame(width: 104)
                }
            } else {
                Text(rangeLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                HStack(spacing: 2) {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(offset >= 0)
                        .opacity(offset >= 0 ? 0.35 : 1)
                }
                .buttonStyle(RoundIconButtonStyle())
            }

            Menu {
                ForEach(Period.allCases) { p in
                    Button(p.rawValue) {
                        period = p
                        offset = 0
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                    Text(period.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var tiles: some View {
        HStack(spacing: 14) {
            tile("Total time", DurationFormat.hms(totalSeconds), sub: "\(entries.count) entries")
            tile("Earned", String(format: "$%.2f", totalAmount), sub: slices.first.map { "\($0.client) $\(String(format: "%.2f", $0.amount))" } ?? "—")
            tile("Top client", slices.first?.client ?? "—", sub: slices.first.map { DurationFormat.hms($0.seconds) } ?? "")
            tile("Busiest day",
                 busiestDay.map { Self.shortDay.string(from: $0.0) } ?? "—",
                 sub: busiestDay.map { DurationFormat.hms($0.1) } ?? "")
        }
    }

    private func tile(_ label: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textDim)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
    }

    private func cardTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textDim)
    }

    private var emptyNote: some View {
        Text("Nothing tracked in this period.")
            .font(Theme.rounded)
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: Charts

    private var axisStride: Int {
        dayCount <= 14 ? 1 : (dayCount <= 45 ? 3 : 7)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(clientNames, id: \.self) { name in
                HStack(spacing: 6) {
                    Circle().fill(color(for: name)).frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var xDomain: ClosedRange<Date> {
        let end = max(range.end, range.start.addingTimeInterval(86_400))
        return range.start...end
    }

    private var barChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            Chart(dayBars) { b in
                BarMark(x: .value("Day", b.day, unit: .day),
                        y: .value("Hours", b.hours))
                    .foregroundStyle(color(for: b.client))
                    .cornerRadius(3)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h))
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
        }
    }

    private var donut: some View {
        HStack(spacing: 16) {
            ZStack {
                Chart(slices) { s in
                    SectorMark(angle: .value("Time", s.seconds),
                               innerRadius: .ratio(0.64),
                               angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(color(for: s.client))
                }
                .chartLegend(.hidden)
                Text(DurationFormat.hms(totalSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { s in
                    HStack(spacing: 8) {
                        Circle().fill(color(for: s.client)).frame(width: 8, height: 8)
                        Text(s.client)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(DurationFormat.hms(s.seconds))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Text(totalSeconds > 0 ? String(format: "%.0f%%", s.seconds / totalSeconds * 100) : "")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textFaint)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(activities.prefix(10).enumerated()), id: \.element.id) { index, a in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                HStack(spacing: 10) {
                    Circle().fill(color(for: a.client)).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(a.project.map { "\(a.client) · \($0)" } ?? a.client)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Text(DurationFormat.hms(a.seconds))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 7)
            }
        }
    }
}
