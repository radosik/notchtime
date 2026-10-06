import SwiftUI
import NotchTimeCore

/// Black slab that grows out of the notch: square top (flush with the screen edge), rounded bottom.
struct IslandShape: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return UnevenRoundedRectangle(topLeadingRadius: 0,
                                      bottomLeadingRadius: radius,
                                      bottomTrailingRadius: radius,
                                      topTrailingRadius: 0,
                                      style: .continuous).path(in: r)
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var s = self
        s.inset += amount
        return s
    }
}

struct IslandRootView: View {
    @ObservedObject var store: TimeStore
    @ObservedObject var model: IslandModel
    let actions: IslandActions

    var body: some View {
        let m = model.metrics
        let running = store.running
        let expanded = model.isExpanded
        let width: CGFloat = expanded ? m.expandedWidth : (running != nil ? m.collapsedRunningWidth : m.collapsedIdleWidth)
        let height: CGFloat = expanded ? m.expandedHeight : m.notchHeight
        let radius: CGFloat = expanded ? 30 : (running != nil ? 16 : 12)

        ZStack(alignment: .top) {
            IslandShape(radius: radius)
                .fill(Theme.islandSurface)
                .overlay(
                    IslandShape(radius: radius)
                        .strokeBorder(Theme.edge, lineWidth: 0.6)
                        .opacity(expanded ? 1 : 0)
                )
                .shadow(color: Color.black.opacity(expanded ? 0.6 : 0.0), radius: 22, x: 0, y: 12)

            if expanded {
                ExpandedIsland(store: store, model: model, actions: actions)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            } else if let running {
                CompactRunning(entry: running, now: store.now, metrics: m)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: running != nil)
        .frame(width: m.expandedWidth, height: m.expandedHeight, alignment: .top)
    }
}

// MARK: - Collapsed, timer running

struct CompactRunning: View {
    let entry: TimeEntry
    let now: Date
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 0) {
            Text(DurationFormat.compact(entry.duration(now: now)))
                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: metrics.sideWidth)

            Color.clear.frame(width: metrics.notchWidth)

            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.tongueTop)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.tongueTop.opacity(0.9), radius: 4)
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: metrics.sideWidth - 10)
            .padding(.leading, 4)
        }
        .frame(height: metrics.notchHeight)
    }
}

// MARK: - Expanded

struct ExpandedIsland: View {
    @ObservedObject var store: TimeStore
    @ObservedObject var model: IslandModel
    let actions: IslandActions
    @FocusState private var titleFocused: Bool

    private var running: TimeEntry? { store.running }

    var body: some View {
        let m = model.metrics
        VStack(spacing: 0) {
            // Level with the notch, left and right of it; chips sit 10 pt below the screen edge.
            HStack {
                ClientMenu(store: store, model: model)
                Spacer(minLength: 0)
                MoreMenu(actions: actions)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .frame(width: m.expandedWidth, height: m.controlsRowHeight, alignment: .top)

            Text(timerText)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(running != nil ? Theme.text : Theme.textFaint)
                .padding(.top, 6)

            GhostField(placeholder: "What are you working on?",
                       text: $model.draftTitle,
                       font: .system(size: 14.5, weight: .medium, design: .rounded)) {
                if running == nil { start() }
            }
            .focused($titleFocused)
            .padding(.horizontal, 36)
            .padding(.top, 2)
            .onChange(of: model.draftTitle) { _, new in
                if running != nil { store.updateRunning(title: new) }
            }

            HStack(alignment: .center, spacing: 10) {
                if let r = running {
                    StartedAt(entry: r, model: model, store: store)
                } else {
                    RecentChips(store: store, restart: restart)
                }
                Spacer(minLength: 8)
                if running != nil {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(PillowButtonStyle(tint: .tongue, size: 13, horizontal: 20, vertical: 8))
                    .help("Stop")
                } else {
                    Button(action: start) {
                        Image(systemName: "play.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(PillowButtonStyle(tint: .cloud, size: 13, horizontal: 20, vertical: 8))
                    .help("Start")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: m.expandedWidth, height: m.expandedHeight, alignment: .top)
        .onAppear {
            model.startText = ""
            model.isEditingStart = false
        }
    }

    private var timerText: String {
        if let r = running { return DurationFormat.hms(r.duration(now: store.now)) }
        return "00:00:00"
    }

    private func start() {
        actions.pin()
        store.start(title: model.draftTitle, clientID: model.draftClientID, project: model.draftProject)
    }

    private func stop() {
        store.stop()
        model.draftTitle = ""
        model.isEditingStart = false
    }

    private func restart(_ e: TimeEntry) {
        actions.pin()
        model.draftTitle = e.title
        model.draftClientID = e.clientID
        model.draftProject = e.project
        store.start(title: e.title, clientID: e.clientID, project: e.project)
    }
}

// MARK: - Pieces

struct ClientMenu: View {
    @ObservedObject var store: TimeStore
    @ObservedObject var model: IslandModel

    private var label: String {
        guard let c = store.client(id: model.draftClientID) else { return "No client" }
        if let p = model.draftProject, !p.isEmpty { return "\(c.name) · \(p)" }
        return c.name
    }

    var body: some View {
        Menu {
            ForEach(store.clients) { c in
                if c.projects.isEmpty {
                    Button(c.name) { pick(c, nil) }
                } else {
                    Menu(c.name) {
                        Button("No project") { pick(c, nil) }
                        Divider()
                        ForEach(c.projects, id: \.self) { p in
                            Button(p) { pick(c, p) }
                        }
                    }
                }
            }
            Divider()
            Button("No client") { pick(nil, nil) }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(model.draftClientID == nil ? Theme.textDim : Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func pick(_ c: Client?, _ project: String?) {
        model.draftClientID = c?.id
        model.draftProject = project
        if store.running != nil {
            store.updateRunning(clientID: .some(c?.id), project: .some(project))
        }
    }
}

struct MoreMenu: View {
    let actions: IslandActions

    var body: some View {
        Menu {
            Button("History…") { actions.showHistory() }
            Button("Export this month…") { actions.exportMonth() }
            Divider()
            Button("Settings…") { actions.showSettings() }
            Divider()
            Button("Quit NotchTime") { actions.quit() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// "Started 14:47" → click → type a new HH:mm to count from.
struct StartedAt: View {
    let entry: TimeEntry
    @ObservedObject var model: IslandModel
    @ObservedObject var store: TimeStore
    @FocusState private var focused: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            if model.isEditingStart {
                Text("Count from")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                TextField("HH:mm", text: $model.startText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand {
                        model.isEditingStart = false
                    }
                Button("Set", action: commit)
                    .buttonStyle(PillowButtonStyle(tint: .ghost, size: 12, horizontal: 12, vertical: 6))
            } else {
                Button {
                    model.startText = Self.timeFormatter.string(from: entry.start)
                    model.isEditingStart = true
                    DispatchQueue.main.async { focused = true }
                } label: {
                    HStack(spacing: 5) {
                        Text("Started \(Self.timeFormatter.string(from: entry.start))")
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commit() {
        if let date = Self.parse(model.startText, relativeTo: Date()) {
            store.setRunningStart(date)
        }
        model.isEditingStart = false
    }

    /// "14:47" → today at 14:47, or yesterday if that would be in the future.
    static func parse(_ text: String, relativeTo now: Date) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        let cal = Calendar.current
        guard var date = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
        if date > now { date = cal.date(byAdding: .day, value: -1, to: date) ?? date }
        return date
    }
}

struct RecentChips: View {
    @ObservedObject var store: TimeStore
    let restart: (TimeEntry) -> Void

    var body: some View {
        let recent = store.recent(limit: 3)
        if recent.isEmpty {
            Text("Hover the notch any time to start a timer.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                ForEach(recent) { e in
                    Button { restart(e) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8, weight: .bold))
                            Text(e.title.isEmpty ? "Untitled" : e.title)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 110)
                }
            }
        }
    }
}
