import Foundation

/// A single clipboard history entry.
///
/// - `.text`  is stored inline.
/// - `.image` is stored as a PNG or JPEG file next to the history file.
/// - `.file`  records the location of files copied in Finder. Only the paths
///            are stored, never a copy of the file itself.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
        case file
    }

    let id: UUID
    let kind: Kind
    var createdAt: Date
    /// SHA-256 of the content (text bytes, image bytes, or joined paths).
    let contentHash: String
    /// Size in bytes: UTF-8 text, encoded image, or total size of the files.
    let byteCount: Int
    /// Present for `.text` items.
    var text: String?
    /// Present for `.image` items; file name (with extension) inside the images directory.
    var imageFileName: String?
    /// Pixel size for images, used for display.
    var imageWidth: Int?
    var imageHeight: Int?
    /// Present for `.file` items; absolute paths of the copied files.
    var filePaths: [String]?

    // MARK: - Factories

    static func text(_ string: String) -> ClipItem {
        let data = Data(string.utf8)
        return ClipItem(
            id: UUID(),
            kind: .text,
            createdAt: Date(),
            contentHash: Hashing.sha256Hex(data),
            byteCount: data.count,
            text: string
        )
    }

    static func image(data: Data, fileExtension: String, width: Int, height: Int) -> ClipItem {
        let id = UUID()
        return ClipItem(
            id: id,
            kind: .image,
            createdAt: Date(),
            contentHash: Hashing.sha256Hex(data),
            byteCount: data.count,
            imageFileName: "\(id.uuidString).\(fileExtension)",
            imageWidth: width,
            imageHeight: height
        )
    }

    static func files(_ urls: [URL]) -> ClipItem {
        let paths = urls.map(\.path)
        let joined = paths.joined(separator: "\n")
        let totalSize = urls.reduce(0) { sum, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { return sum }
            return sum + (values?.fileSize ?? 0)
        }
        return ClipItem(
            id: UUID(),
            kind: .file,
            createdAt: Date(),
            contentHash: Hashing.sha256Hex(Data(joined.utf8)),
            byteCount: totalSize,
            filePaths: paths
        )
    }

    init(
        id: UUID,
        kind: Kind,
        createdAt: Date,
        contentHash: String,
        byteCount: Int,
        text: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        filePaths: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.contentHash = contentHash
        self.byteCount = byteCount
        self.text = text
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
    }

    // MARK: - Files

    var fileURLs: [URL] {
        (filePaths ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// File URLs that still exist on disk.
    var existingFileURLs: [URL] {
        fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// True when at least one referenced file has been moved or deleted.
    var hasMissingFiles: Bool {
        kind == .file && existingFileURLs.count != fileURLs.count
    }

    // MARK: - Display

    /// A compact single-paragraph preview suitable for a list row.
    var preview: String {
        switch kind {
        case .text:
            let raw = text ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let collapsed = trimmed
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ⏎ ")
            if collapsed.count > 300 {
                return String(collapsed.prefix(300)) + "…"
            }
            return collapsed
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "Image \(w)×\(h)"
            }
            return "Image"
        case .file:
            let names = fileURLs.map(\.lastPathComponent)
            switch names.count {
            case 0: return "File"
            case 1: return names[0]
            case 2, 3: return names.joined(separator: ", ")
            default: return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
            }
        }
    }

    /// Secondary line: counts for text, size for images, location for files.
    var detail: String {
        switch kind {
        case .text:
            let raw = text ?? ""
            let lines = raw.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).count
            let chars = raw.count
            let lineWord = lines == 1 ? "line" : "lines"
            let charWord = chars == 1 ? "character" : "characters"
            return "\(chars) \(charWord) · \(lines) \(lineWord)"
        case .image:
            let format = (imageFileName as NSString?)?.pathExtension.uppercased() ?? "PNG"
            return "\(format) · " + ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        case .file:
            let urls = fileURLs
            if urls.count == 1, let url = urls.first {
                let folder = url.deletingLastPathComponent().path
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let shown = folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
                return String(shown)
            }
            return "\(urls.count) files · " + ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }
}
