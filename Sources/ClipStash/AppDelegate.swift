import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private var monitor: ClipboardMonitor!
    private var paster: PasteService!
    private var panelController: HistoryPanelController!
    private var statusBar: StatusBarController!
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        store.load()

        monitor = ClipboardMonitor(store: store)
        monitor.start()

        paster = PasteService(store: store, monitor: monitor)

        panelController = HistoryPanelController(store: store, paster: paster)
        panelController.onOpenSettings = { [weak self] in self?.showSettings() }

        statusBar = StatusBarController()
        statusBar.onShowHistory = { [weak self] in self?.panelController.show() }
        statusBar.onOpenSettings = { [weak self] in self?.showSettings() }
        statusBar.onClearAll = { [weak self] in self?.confirmClearAll() }
        statusBar.onQuit = { NSApp.terminate(nil) }

        HotKeyManager.shared.onTrigger = { [weak self] in self?.panelController.toggle() }
        if !HotKeyManager.shared.register(AppSettings.shared.hotKey) {
            // Fall back to the default if a stored combo can no longer be registered.
            AppSettings.shared.resetHotKeyToDefault()
            HotKeyManager.shared.register(AppSettings.shared.hotKey)
        }

        handleFirstLaunchIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Double-clicking the app in Finder while it is running opens the panel.
        panelController.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Actions

    private func showSettings() {
        settingsWindow.show(store: store)
    }

    private func confirmClearAll() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This permanently deletes every stored item from this Mac. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    private func handleFirstLaunchIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.hasLaunchedBefore else { return }
        settings.hasLaunchedBefore = true

        // Start at login by default; the user can turn it off in Settings.
        try? LoginItemManager.setEnabled(true)

        // Ask for Accessibility so paste-on-select works, then show Settings so
        // the user can see the app is running and what the hotkey is.
        PasteService.requestAccessibility()
        showSettings()
    }

    // MARK: - Main menu

    /// An accessory app has no visible menu bar, but a main menu is still
    /// required for standard Edit shortcuts (⌘C, ⌘V, ⌘A…) to work inside our
    /// own text fields, and for ⌘Q / ⌘W in the Settings window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ClipStash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuOpenSettings() {
        showSettings()
    }
}
