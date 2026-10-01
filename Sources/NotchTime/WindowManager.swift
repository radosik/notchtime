import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NotchTimeCore

/// Regular (titled) windows: history and settings. Also runs the export save panel.
final class WindowManager {
    let store: TimeStore
    private var windows: [String: NSWindow] = [:]

    init(store: TimeStore) {
        self.store = store
    }

    func showHistory() {
        show(key: "history", title: "History", size: CGSize(width: 600, height: 680)) {
            HistoryView(store: store,
                        export: { [weak self] month in self?.export(month: month) },
                        restart: { [weak self] e in
                            _ = self?.store.start(title: e.title, clientID: e.clientID, project: e.project)
                        })
        }
    }

    func showSettings() {
        show(key: "settings", title: "Settings", size: CGSize(width: 560, height: 420)) {
            SettingsView(store: store)
        }
    }

    private func show<V: View>(key: String, title: String, size: CGSize, @ViewBuilder content: () -> V) {
        let window: NSWindow
        if let existing = windows[key] {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
            window.title = title
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0x17 / 255, green: 0x19 / 255, blue: 0x1D / 255, alpha: 1)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.setFrameAutosaveName("NotchTime.\(key)")
            window.center()
            windows[key] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func export(month: Date) {
        guard let range = Calendar.current.dateInterval(of: .month, for: month) else { return }
        let entries = store.entries(in: range)
        let data = ReportExporter.workbook(entries: entries, clients: store.clients, range: range)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = ReportExporter.suggestedFilename(reportName: store.reportName, range: range)
        panel.canCreateDirectories = true
        panel.title = "Export monthly report"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the report"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
