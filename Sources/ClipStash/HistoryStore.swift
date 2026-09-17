import AppKit
import Combine
import Foundation

/// Owns the clipboard history and persists it to disk.
///
/// Everything lives under `~/Library/Application Support/ClipStash/`:
///   - `history.json`  the ordered list of items (newest first)
///   - `images/`       PNG payloads for image items
///
/// Nothing ever leaves the local machine.
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let directoryURL: URL
    let historyFileURL: URL
    let imagesDirectoryURL: URL

    private let ioQueue = DispatchQueue(label: "com.clipstash.store.io", qos: .utility)
    private let thumbnailCache = NSCache<NSString, NSImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("ClipStash", isDirectory: true)
        historyFileURL = directoryURL.appendingPathComponent("history.json")
        imagesDirectoryURL = directoryURL.appendingPathComponent("images", isDirectory: true)
        thumbnailCache.countLimit = 200
    }

    // MARK: - Loading / saving

    func load() {
        ensureDirectories()
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipItem].self, from: data) {
            // Drop image items whose file has gone missing.
            items = decoded.filter { item in
                guard item.kind == .image, let name = item.imageFileName else { return true }
                return FileManager.default.fileExists(atPath: imagesDirectoryURL.appendingPathComponent(name).path)
            }
        }
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }

    private func persist() {
        let snapshot = items
        let url = historyFileURL
        ioQueue.async { [weak self] in
            self?.ensureDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Mutation

    func addText(_ string: String) {
        let candidate = ClipItem.text(string)
        insert(candidate)
    }

    func addImage(pngData: Data, width: Int, height: Int) {
        let candidate = ClipItem.image(pngData: pngData, width: width, height: height)
        if let existingIndex = items.firstIndex(where: { $0.contentHash == candidate.contentHash }) {
            moveToTop(items[existingIndex].id)
            return
        }
        ensureDirectories()
        let fileURL = imagesDirectoryURL.appendingPathComponent(candidate.imageFileName!)
        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        insert(candidate)
    }

    private func insert(_ candidate: ClipItem) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == candidate.contentHash }) {
            // Same content already exists: refresh its position rather than duplicating.
            var existing = items.remove(at: existingIndex)
            existing = ClipItem(
                id: existing.id,
                kind: existing.kind,
                createdAt: Date(),
                contentHash: existing.contentHash,
                byteCount: existing.byteCount,
                text: existing.text,
                imageFileName: existing.imageFileName,
                imageWidth: existing.imageWidth,
                imageHeight: existing.imageHeight
            )
            items.insert(existing, at: 0)
        } else {
            items.insert(candidate, at: 0)
        }
        trimIfNeeded()
        persist()
    }

    /// Moves an item to the top of the list and refreshes its timestamp,
    /// so the item selected from history becomes the "most recently copied".
    func moveToTop(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        items.insert(touched(item), at: 0)
        persist()
    }

    private func touched(_ item: ClipItem) -> ClipItem {
        ClipItem(
            id: item.id,
            kind: item.kind,
            createdAt: Date(),
            contentHash: item.contentHash,
            byteCount: item.byteCount,
            text: item.text,
            imageFileName: item.imageFileName,
            imageWidth: item.imageWidth,
            imageHeight: item.imageHeight
        )
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        deleteImageFile(for: item)
        persist()
    }

    /// Removes every item and every file on disk. This is the "Clear All" action.
    func clearAll() {
        items.removeAll()
        thumbnailCache.removeAllObjects()
        let dir = directoryURL
        let imagesDir = imagesDirectoryURL
        let history = historyFileURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: history)
            try? FileManager.default.removeItem(at: imagesDir)
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            _ = dir
        }
    }

    func applyMaxItems() {
        trimIfNeeded()
        persist()
    }

    private func trimIfNeeded() {
        let limit = max(1, AppSettings.shared.maxItems)
        guard items.count > limit else { return }
        let overflow = items[limit...]
        for item in overflow { deleteImageFile(for: item) }
        items.removeLast(items.count - limit)
    }

    private func deleteImageFile(for item: ClipItem) {
        guard item.kind == .image, let name = item.imageFileName else { return }
        thumbnailCache.removeObject(forKey: name as NSString)
        let url = imagesDirectoryURL.appendingPathComponent(name)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Image access

    func imageData(for item: ClipItem) -> Data? {
        guard item.kind == .image, let name = item.imageFileName else { return nil }
        return try? Data(contentsOf: imagesDirectoryURL.appendingPathComponent(name))
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let name = item.imageFileName else { return nil }
        if let cached = thumbnailCache.object(forKey: name as NSString) { return cached }
        guard let data = imageData(for: item), let image = NSImage(data: data) else { return nil }
        thumbnailCache.setObject(image, forKey: name as NSString)
        return image
    }

    // MARK: - Stats

    var approximateByteCount: Int {
        items.reduce(0) { $0 + $1.byteCount }
    }
}
