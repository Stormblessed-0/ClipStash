import AppKit
import Carbon
import SwiftUI

/// A floating panel that can take keyboard focus without activating the app,
/// so the app the user was typing in stays frontmost and receives the paste.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class HistoryPanelController: NSObject, NSWindowDelegate {
    let panel: HistoryPanel
    let model: HistoryViewModel

    var onOpenSettings: (() -> Void)?

    private let store: HistoryStore
    private let paster: PasteService
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    init(store: HistoryStore, paster: PasteService) {
        self.store = store
        self.paster = paster
        self.model = HistoryViewModel(store: store)
        self.panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 380, height: 300)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(model: model, store: store))

        model.onSelect = { [weak self] item, paste in self?.handleSelect(item, paste: paste) }
        model.onClose = { [weak self] in self?.hide() }
        model.onOpenSettings = { [weak self] in
            self?.hide()
            self?.onOpenSettings?()
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.reset()
        positionNearMouse()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
            self?.focusSearchField()
        }
    }

    func hide() {
        removeKeyMonitor()
        model.disarmClear()
        panel.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the popup, like a menu.
        hide()
    }

    // MARK: - Selection

    private func handleSelect(_ item: ClipItem, paste: Bool) {
        let target = previousApp
        hide()
        paster.select(item, target: target, paste: paste && AppSettings.shared.pasteOnSelect)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            guard event.window == nil || event.window === self.panel else { return event }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            switch Int(event.keyCode) {
            case kVK_DownArrow:
                self.model.moveSelection(by: 1)
                return nil
            case kVK_UpArrow:
                self.model.moveSelection(by: -1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.model.selectCurrent(paste: !flags.contains(.shift))
                return nil
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_Delete where flags.contains(.command):
                self.model.deleteSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func focusSearchField() {
        guard let content = panel.contentView, let field = Self.findTextField(in: content) else { return }
        panel.makeFirstResponder(field)
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Positioning

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height + 24)
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        panel.setFrameOrigin(origin)
    }
}
