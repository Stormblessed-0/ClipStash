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
        let wrote = writeToPasteboard(item)
        store.moveToTop(item.id)
        // Nothing usable (for example a file that no longer exists): leave the
        // clipboard alone and do not send a keystroke.
        guard wrote, paste else { return }

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

    /// Returns false when the item could not be placed on the pasteboard.
    @discardableResult
    private func writeToPasteboard(_ item: ClipItem) -> Bool {
        let pasteboard = NSPasteboard.general
        var wrote = false
        switch item.kind {
        case .text:
            pasteboard.clearContents()
            wrote = pasteboard.setString(item.text ?? "", forType: .string)

        case .image:
            // Offer the original bytes (JPEG or PNG) plus TIFF, which macOS
            // can translate into whatever flavor the receiving app asks for.
            guard let data = store.imageData(for: item), let image = NSImage(data: data) else { break }
            let originalType = store.imagePasteboardType(for: item)
            pasteboard.clearContents()
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: originalType)
            if let tiff = image.tiffRepresentation {
                pasteboardItem.setData(tiff, forType: .tiff)
            }
            wrote = pasteboard.writeObjects([pasteboardItem])

        case .file:
            // One pasteboard item per file, each carrying its file URL. The
            // first item also carries the file names as plain text so pasting
            // into a text field yields something sensible.
            let urls = item.existingFileURLs
            guard !urls.isEmpty else { break }
            pasteboard.clearContents()
            let names = urls.map(\.lastPathComponent).joined(separator: "\n")
            let pasteboardItems: [NSPasteboardItem] = urls.enumerated().map { index, url in
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                if index == 0 {
                    pasteboardItem.setString(names, forType: .string)
                }
                return pasteboardItem
            }
            wrote = pasteboard.writeObjects(pasteboardItems)
        }
        monitor.markOwnChange()
        return wrote
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

    /// Whether the system Accessibility prompt has been shown this session.
    /// It is shown at most once per launch so a missing grant never turns
    /// into a prompt on every single selection.
    private var hasPromptedForAccessibility = false

    private func sendPasteKeystroke() {
        guard Self.isAccessibilityTrusted else {
            // The item is already on the clipboard, so the user can still ⌘V by hand.
            if !hasPromptedForAccessibility {
                hasPromptedForAccessibility = true
                Self.requestAccessibility()
            }
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
