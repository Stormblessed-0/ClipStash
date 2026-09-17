import Combine
import Foundation

/// User preferences, backed by `UserDefaults` (stored locally in
/// `~/Library/Preferences/com.clipstash.app.plist`).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let hotKey = "hotKey"
        static let maxItems = "maxItems"
        static let pasteOnSelect = "pasteOnSelect"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    private let defaults = UserDefaults.standard

    @Published var hotKey: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    /// Upper bound on stored history entries. Oldest entries are dropped first.
    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    /// When true, selecting an item also sends ⌘V to the frontmost app.
    /// When false, selecting only places the item on the clipboard.
    @Published var pasteOnSelect: Bool {
        didSet { defaults.set(pasteOnSelect, forKey: Keys.pasteOnSelect) }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Keys.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Keys.hasLaunchedBefore) }
    }

    private init() {
        if let data = defaults.data(forKey: Keys.hotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .defaultCombo
        }
        let storedMax = defaults.integer(forKey: Keys.maxItems)
        maxItems = storedMax > 0 ? storedMax : 500
        pasteOnSelect = defaults.object(forKey: Keys.pasteOnSelect) as? Bool ?? true
    }

    func resetHotKeyToDefault() {
        hotKey = .defaultCombo
    }
}
