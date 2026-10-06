import AppKit
import NotchTimeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TimeStore!
    private var windows: WindowManager!
    private var notch: NotchController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon; lives on the notch only
        MainMenu.install()

        store = TimeStore()
        windows = WindowManager(store: store)

        var actions = IslandActions()
        actions.showHistory = { [weak self] in
            self?.notch.collapse()
            self?.windows.showHistory()
        }
        actions.showSettings = { [weak self] in
            self?.notch.collapse()
            self?.windows.showSettings()
        }
        actions.exportMonth = { [weak self] in
            self?.notch.collapse()
            self?.windows.export(month: Date())
        }
        actions.quit = { NSApp.terminate(nil) }

        notch = NotchController(store: store, actions: actions)
    }

    /// Opening the app again (Finder / Launchpad) while it is running shows History,
    /// which doubles as an escape hatch if the island is ever hard to reach.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showHistory()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum MainMenu {
    /// A minimal main menu so ⌘C/⌘V/⌘A/⌘Z work inside text fields of an accessory app.
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit NotchTime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
