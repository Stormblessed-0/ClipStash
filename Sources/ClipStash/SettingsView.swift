import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings = .shared
    @ObservedObject var store: HistoryStore

    @State private var isRecording = false
    @State private var recordMonitor: Any?
    @State private var hotKeyError: String?
    @State private var loginStatus = LoginItemManager.status
    @State private var loginError: String?
    @State private var accessibilityTrusted = PasteService.isAccessibilityTrusted
    @State private var clearArmed = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    static let repositoryURL = URL(string: "https://github.com/dominic-barnard/ClipStash")!

    var body: some View {
        Form {
            shortcutSection
            behaviorSection
            permissionsSection
            storageSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onReceive(refreshTimer) { _ in refreshStatus() }
        .onDisappear { stopRecording() }
    }

    // MARK: Sections

    private var shortcutSection: some View {
        Section {
            HStack {
                Text("Show clipboard history")
                Spacer()
                Text(isRecording ? "Press new shortcut…" : settings.hotKey.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Button(isRecording ? "Cancel" : "Change…") { toggleRecording() }
                Button("Reset") { applyHotKey(.defaultCombo) }
                    .disabled(settings.hotKey == .defaultCombo || isRecording)
            }
            if let hotKeyError {
                Text(hotKeyError).font(.caption).foregroundStyle(.red)
            }
            Text(isRecording
                 ? "Hold one or more of ⌃ ⌥ ⇧ ⌘ and press a key. Press esc to cancel."
                 : "The default is ⌃' (Control + apostrophe). The shortcut must include at least one modifier key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Keyboard Shortcut")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Launch ClipStash at login", isOn: Binding(
                get: { loginStatus.isEnabled },
                set: { setLoginEnabled($0) }
            ))
            if loginStatus == .requiresApproval {
                HStack {
                    Text("macOS needs you to approve this in Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") { LoginItemManager.openLoginItemsSettings() }
                }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Toggle("Paste automatically when an item is selected", isOn: $settings.pasteOnSelect)
            Text(settings.pasteOnSelect
                 ? "Selecting an item copies it and pastes it into the app you were using."
                 : "Selecting an item only copies it to the clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: $settings.maxItems, in: 50...5000, step: 50) {
                Text("Keep up to \(settings.maxItems) items")
            }
            .onChange(of: settings.maxItems) { _ in store.applyMaxItems() }
            Text("Older items are removed automatically once the limit is reached.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Behavior")
        }
    }

    private var permissionsSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                    Text("Required to paste automatically. Without it, items are still copied to the clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if accessibilityTrusted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant…") {
                        PasteService.requestAccessibility()
                        PasteService.openAccessibilitySettings()
                    }
                }
            }
        } header: {
            Text("Permissions")
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(storageSummary)
                    Text(store.directoryURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.directoryURL])
                }
            }
            HStack {
                Button(role: .destructive) {
                    if clearArmed {
                        store.clearAll()
                        clearArmed = false
                    } else {
                        clearArmed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { clearArmed = false }
                    }
                } label: {
                    Label(clearArmed ? "Confirm: Clear All History" : "Clear All History…", systemImage: "trash")
                }
                .tint(.red)
                .disabled(store.items.isEmpty)
                Spacer()
            }
            Text("Everything ClipStash records stays in this folder on your Mac. Nothing is uploaded or synced.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Storage")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("ClipStash \(Self.versionString)")
                Spacer()
                Link("Source on GitHub", destination: Self.repositoryURL)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: Helpers

    private var storageSummary: String {
        let count = store.items.count
        let noun = count == 1 ? "item" : "items"
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.approximateByteCount), countStyle: .file)
        return "\(count) \(noun) · \(size)"
    }

    static var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "development build"
    }

    private func refreshStatus() {
        accessibilityTrusted = PasteService.isAccessibilityTrusted
        loginStatus = LoginItemManager.status
    }

    private func setLoginEnabled(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = LoginItemManager.status
    }

    // MARK: Hotkey recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        isRecording = true
        hotKeyError = nil
        // Release the current registration so the same combo can be re-recorded.
        HotKeyManager.shared.unregister()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            guard let combo = KeyCombo(event: event) else {
                hotKeyError = "Include at least one modifier key (⌃ ⌥ ⇧ ⌘)."
                return nil
            }
            stopRecording()
            applyHotKey(combo)
            return nil
        }
    }

    private func stopRecording() {
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
            self.recordMonitor = nil
        }
        isRecording = false
        if HotKeyManager.shared.current == nil {
            HotKeyManager.shared.register(settings.hotKey)
        }
    }

    private func applyHotKey(_ combo: KeyCombo) {
        if HotKeyManager.shared.register(combo) {
            settings.hotKey = combo
            hotKeyError = nil
        } else {
            hotKeyError = "That shortcut could not be registered. It is probably reserved by macOS or another app."
            HotKeyManager.shared.register(settings.hotKey)
        }
    }
}

// MARK: - Window

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(store: HistoryStore) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClipStash Settings"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
