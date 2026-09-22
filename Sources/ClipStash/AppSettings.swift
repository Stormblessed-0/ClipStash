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
        static let recordFiles = "recordFiles"
        static let compressLargeImages = "compressLargeImages"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    /// When true, files copied in Finder are recorded (by location, not content).
    @Published var recordFiles: Bool {
        didSet { defaults.set(recordFiles, forKey: Keys.recordFiles) }
    }

    /// When true, large opaque images are stored as JPEG instead of as copied.
    /// Off by default so images are kept exactly as the source app provided them.
    @Published var compressLargeImages: Bool {
        didSet { defaults.set(compressLargeImages, forKey: Keys.compressLargeImages) }
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
        recordFiles = defaults.object(forKey: Keys.recordFiles) as? Bool ?? true
        compressLargeImages = defaults.object(forKey: Keys.compressLargeImages) as? Bool ?? false
    }

    func resetHotKeyToDefault() {
        hotKey = .defaultCombo
    }
}
