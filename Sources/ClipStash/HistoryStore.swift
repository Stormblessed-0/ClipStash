import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns the clipboard history and persists it to disk.
///
/// Everything lives under `~/Library/Application Support/ClipStash/`:
///   - `history.json`          the ordered list of items (newest first)
///   - `images/`               PNG/JPEG payloads for image items
///   - `history.pre-1.1.json`  one-time backup taken before the 1.1 format
///                             (adds file items) was first written
///
/// Nothing ever leaves the local machine.
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let directoryURL: URL
    let historyFileURL: URL
    let imagesDirectoryURL: URL
    let legacyBackupURL: URL

    private let ioQueue = DispatchQueue(label: "com.clipstash.store.io", qos: .utility)
    private let thumbnailCache = NSCache<NSString, NSImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("ClipStash", isDirectory: true)
        historyFileURL = directoryURL.appendingPathComponent("history.json")
        imagesDirectoryURL = directoryURL.appendingPathComponent("images", isDirectory: true)
        legacyBackupURL = directoryURL.appendingPathComponent("history.pre-1.1.json")
        thumbnailCache.countLimit = 300
    }

    // MARK: - Loading / saving

    func load() {
        ensureDirectories()
        guard let data = try? Data(contentsOf: historyFileURL) else { return }

        // Keep a copy of the last pre-1.1 history so an older ClipStash can
        // still read it if the user ever rolls back.
        if !FileManager.default.fileExists(atPath: legacyBackupURL.path) {
            try? data.write(to: legacyBackupURL, options: .atomic)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Decode item-by-item so one unreadable entry (for example a kind
        // added by a newer version) never discards the whole history.
        guard let decoded = try? decoder.decode([LenientItem].self, from: data) else { return }
        items = decoded.compactMap(\.item).filter { item in
            guard item.kind == .image, let name = item.imageFileName else { return true }
            return FileManager.default.fileExists(atPath: imagesDirectoryURL.appendingPathComponent(name).path)
        }
    }

    private struct LenientItem: Decodable {
        let item: ClipItem?
        init(from decoder: Decoder) throws {
            item = try? ClipItem(from: decoder)
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
        insert(ClipItem.text(string))
    }

    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        insert(ClipItem.files(urls))
    }

    /// Stores encoded image bytes as-is (PNG or JPEG) under the images directory.
    func addImage(data: Data, fileExtension: String, width: Int, height: Int) {
        let candidate = ClipItem.image(data: data, fileExtension: fileExtension, width: width, height: height)
        if let existingIndex = items.firstIndex(where: { $0.contentHash == candidate.contentHash }) {
            moveToTop(items[existingIndex].id)
            return
        }
        ensureDirectories()
        let fileURL = imagesDirectoryURL.appendingPathComponent(candidate.imageFileName!)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        insert(candidate)
    }

    private func insert(_ candidate: ClipItem) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == candidate.contentHash }) {
            // Same content already exists: refresh its position rather than duplicating.
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
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
        var item = items.remove(at: index)
        item.createdAt = Date()
        items.insert(item, at: 0)
        persist()
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
        let imagesDir = imagesDirectoryURL
        let history = historyFileURL
        let backup = legacyBackupURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: history)
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.removeItem(at: imagesDir)
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
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

    func imageURL(for item: ClipItem) -> URL? {
        guard item.kind == .image, let name = item.imageFileName else { return nil }
        return imagesDirectoryURL.appendingPathComponent(name)
    }

    func imageData(for item: ClipItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The pasteboard type matching the stored image's encoding.
    func imagePasteboardType(for item: ClipItem) -> NSPasteboard.PasteboardType {
        let ext = ((item.imageFileName ?? "") as NSString).pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg" ? NSPasteboard.PasteboardType("public.jpeg") : .png
    }

    // MARK: - Thumbnails

    /// A small preview for the row: the image itself for image items, a
    /// downsampled picture for image files, or the Finder icon for other files.
    func thumbnail(for item: ClipItem) -> NSImage? {
        switch item.kind {
        case .text:
            return nil
        case .image:
            guard let name = item.imageFileName else { return nil }
            let key = name as NSString
            if let cached = thumbnailCache.object(forKey: key) { return cached }
            guard let url = imageURL(for: item), let image = Self.downsampledImage(at: url, maxPixels: 400) else { return nil }
            thumbnailCache.setObject(image, forKey: key)
            return image
        case .file:
            guard let url = item.existingFileURLs.first else {
                return NSWorkspace.shared.icon(for: .data)
            }
            let key = "file:\(url.path)" as NSString
            if let cached = thumbnailCache.object(forKey: key) { return cached }
            let image: NSImage
            if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
               let picture = Self.downsampledImage(at: url, maxPixels: 400) {
                image = picture
            } else {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
            thumbnailCache.setObject(image, forKey: key)
            return image
        }
    }

    /// Decodes only a small version of a possibly huge image file.
    private static func downsampledImage(at url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Stats

    var approximateByteCount: Int {
        items.reduce(0) { $0 + ($1.kind == .file ? 0 : $1.byteCount) }
    }
}
