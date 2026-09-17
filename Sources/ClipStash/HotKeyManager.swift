import Carbon
import Foundation

/// Registers a single system-wide hotkey via Carbon's `RegisterEventHotKey`.
/// This works without Accessibility permission and does not require an
/// event tap, which keeps the app lightweight.
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Called on the main thread whenever the registered hotkey is pressed.
    var onTrigger: (() -> Void)?

    private(set) var current: KeyCombo?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x434C_5354 /* 'CLST' */, id: 1)

    private init() {}

    /// Registers `combo`, replacing any existing registration.
    /// Returns `false` if the system refused (usually because another app owns it).
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        current = combo
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                guard status == noErr, pressedID.id == 1 else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { HotKeyManager.shared.onTrigger?() }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }
}
