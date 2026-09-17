import AppKit
import Carbon

/// The menu bar icon and its menu. The app has no Dock icon, so this is the
/// only always-visible entry point besides the hotkey.
final class StatusBarController: NSObject, NSMenuDelegate {
    var onShowHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onClearAll: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipStash")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ClipStash — clipboard history"
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = NSMenuItem(title: "Show Clipboard History", action: #selector(showHistory), keyEquivalent: "")
        show.target = self
        applyDisplayShortcut(AppSettings.shared.hotKey, to: show)
        menu.addItem(show)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(login)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear All History…", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ClipStash", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Shows the hotkey next to the menu item purely for display. The real
    /// registration is handled by `HotKeyManager`; the menu item's own
    /// equivalent is never active because the app has no key window.
    private func applyDisplayShortcut(_ combo: KeyCombo, to item: NSMenuItem) {
        let name = KeyCombo.keyName(for: combo.keyCode)
        guard name.count == 1 else { return }
        item.keyEquivalent = name.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if combo.carbonModifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if combo.carbonModifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if combo.carbonModifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if combo.carbonModifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func showHistory() { onShowHistory?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func clearAll() { onClearAll?() }
    @objc private func quit() { onQuit?() }

    @objc private func toggleLogin() {
        try? LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
    }
}
