import AppKit
import SwiftUI
import Combine
import NotchTimeCore

/// UI state for the island that the SwiftUI views observe.
final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var metrics: NotchMetrics

    // What the user is typing / has picked (mirrors the running entry while one is running).
    @Published var draftTitle = ""
    @Published var draftClientID: UUID?
    @Published var draftProject: String?

    // "Count from HH:mm" editor for a running timer.
    @Published var isEditingStart = false
    @Published var startText = ""

    init(metrics: NotchMetrics) {
        self.metrics = metrics
    }
}

/// Closures the island calls back into AppKit-land with.
struct IslandActions {
    var collapse: () -> Void = {}
    var pin: () -> Void = {}
    var showHistory: () -> Void = {}
    var showSettings: () -> Void = {}
    var exportMonth: () -> Void = {}
    var quit: () -> Void = {}
}

/// Owns the panel over the notch, decides when it expands, and keeps it positioned.
final class NotchController {
    let store: TimeStore
    let model: IslandModel
    private let panel: NotchPanel
    private var hosting: NSHostingView<IslandRootView>!
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var rearmNeeded = false
    private var cancellables = Set<AnyCancellable>()

    init(store: TimeStore, actions: IslandActions) {
        self.store = store
        let metrics = NotchMetrics.measure(screen: NotchMetrics.targetScreen())
        model = IslandModel(metrics: metrics)
        panel = NotchPanel(frame: NSRect(x: 0, y: 0, width: metrics.expandedWidth, height: metrics.expandedHeight))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: metrics.expandedWidth, height: metrics.expandedHeight))
        container.wantsLayer = true
        panel.contentView = container

        var acts = actions
        acts.collapse = { [weak self] in self?.collapse() }
        acts.pin = { [weak self] in self?.pin() }
        let view = NSHostingView(rootView: IslandRootView(store: store, model: model, actions: acts))
        view.sizingOptions = []
        container.addSubview(view)
        hosting = view

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenChanged() }
            .store(in: &cancellables)

        // Re-layout when the timer starts/stops so the compact readout gets room beside the notch.
        store.$entries
            .map { $0.contains { $0.end == nil } }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    private func currentSize() -> CGSize {
        let m = model.metrics
        if model.isExpanded { return CGSize(width: m.expandedWidth, height: m.expandedHeight) }
        if store.running != nil { return CGSize(width: m.collapsedRunningWidth, height: m.notchHeight) }
        return CGSize(width: m.collapsedIdleWidth, height: m.notchHeight)
    }

    /// Resize the panel to exactly the island's current size, keeping the island's top-centre on the notch.
    func layout() {
        let m = model.metrics
        let size = currentSize()
        let frame = NSRect(x: (m.notchMidX - size.width / 2).rounded(),
                           y: m.screenTop - size.height,
                           width: size.width,
                           height: size.height)
        panel.setFrame(frame, display: true)
        let W = m.expandedWidth, H = m.expandedHeight
        hosting.frame = NSRect(x: ((size.width - W) / 2).rounded(), y: size.height - H, width: W, height: H)
    }

    private func screenChanged() {
        let metrics = NotchMetrics.measure(screen: NotchMetrics.targetScreen())
        if metrics != model.metrics { model.metrics = metrics }
        layout()
        panel.orderFrontRegardless()
    }

    /// Island rect for a given state, independent of what size the panel currently has.
    private func islandRect(expanded: Bool) -> NSRect {
        let m = model.metrics
        let w: CGFloat = expanded ? m.expandedWidth : (store.running != nil ? m.collapsedRunningWidth : m.collapsedIdleWidth)
        let h: CGFloat = expanded ? m.expandedHeight : m.notchHeight
        return NSRect(x: m.notchMidX - w / 2, y: m.screenTop - h, width: w, height: h)
    }

    /// Hovering here (the notch itself, plus a few points around it) opens the island.
    private func hotZone() -> NSRect {
        let f = islandRect(expanded: false)
        return NSRect(x: f.minX - 10, y: f.minY - 6, width: f.width + 20, height: f.height + 6)
    }

    /// While open and not pinned, leaving this area closes it.
    private func stayZone() -> NSRect {
        islandRect(expanded: true).insetBy(dx: -22, dy: -22)
    }

    // MARK: - State changes

    func expand() {
        guard !model.isExpanded else { return }
        collapseWork?.cancel()
        syncDraftFromRunning()
        model.isExpanded = true
        layout()
        panel.orderFrontRegardless()
    }

    func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard model.isExpanded else { return }
        model.isExpanded = false
        model.isPinned = false
        model.isEditingStart = false
        // Don't pop straight back open until the cursor has left the notch once.
        rearmNeeded = hotZone().contains(NSEvent.mouseLocation)
        // Let the shrink animation play before the panel itself gets smaller.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self, !self.model.isExpanded else { return }
            if self.panel.isKeyWindow {
                // Hand keyboard focus back to whatever app the user was in.
                self.panel.orderOut(nil)
                self.layout()
                self.panel.orderFrontRegardless()
            } else {
                self.layout()
            }
        }
    }

    func pin() {
        guard model.isExpanded else { return }
        collapseWork?.cancel()
        model.isPinned = true
        panel.makeKey()
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            guard let self, self.model.isExpanded, !self.model.isPinned else { return }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func syncDraftFromRunning() {
        guard let r = store.running else { return }
        model.draftTitle = r.title
        model.draftClientID = r.clientID
        model.draftProject = r.project
    }

    // MARK: - Mouse

    private func installMonitors() {
        func add(_ m: Any?) { if let m { monitors.append(m) } }

        add(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.mouseMoved(NSEvent.mouseLocation)
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.mouseMoved(NSEvent.mouseLocation)
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clickedOutside(at: NSEvent.mouseLocation)
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel {
                self.pin()
            } else if self.model.isExpanded, let w = event.window, w.styleMask.contains(.titled) {
                // A click in one of our own regular windows (history/settings) closes the island.
                self.clickedOutside(at: NSEvent.mouseLocation)
            }
            return event
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 { // esc
                self.collapse()
                return nil
            }
            return event
        })
    }

    private func mouseMoved(_ p: NSPoint) {
        if !model.isExpanded {
            let inside = hotZone().contains(p)
            if rearmNeeded {
                if !inside { rearmNeeded = false }
                return
            }
            if inside { expand() }
            return
        }
        guard !model.isPinned else { return }
        if stayZone().contains(p) {
            collapseWork?.cancel()
            collapseWork = nil
        } else {
            scheduleCollapse()
        }
    }

    private func clickedOutside(at p: NSPoint) {
        guard model.isExpanded, !panel.frame.contains(p) else { return }
        collapse()
    }
}
