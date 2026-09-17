import AppKit
import ApplicationServices
import Foundation

/// Puts a history item back on the clipboard and (optionally) pastes it into
/// the app that was in front when the history panel opened.
final class PasteService {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    /// Copies `item` to the clipboard, makes it the most recent history entry,
    /// and if `paste` is true sends ⌘V to `target` (or the frontmost app).
    func select(_ item: ClipItem, target: NSRunningApplication?, paste: Bool) {
        writeToPasteboard(item)
        store.moveToTop(item.id)
        guard paste else { return }

        if let target, !target.isActive {
            if #available(macOS 14.0, *) {
                target.activate()
            } else {
                target.activate(options: [])
            }
        }
        // Give the target a moment to become active and accept key input.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            self?.sendPasteKeystroke()
        }
    }

    private func writeToPasteboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = store.imageData(for: item), let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }
        monitor.markOwnChange()
    }

    // MARK: - Accessibility

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open Accessibility settings.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func sendPasteKeystroke() {
        guard Self.isAccessibilityTrusted else {
            // The item is already on the clipboard, so the user can still ⌘V by hand.
            Self.requestAccessibility()
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(9) // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
