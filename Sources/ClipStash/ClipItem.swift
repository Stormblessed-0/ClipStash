import Foundation

/// A single clipboard history entry. Text is stored inline; images are stored
/// as PNG files next to the history file and referenced by name.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    /// SHA-256 of the content, used to de-duplicate entries.
    let contentHash: String
    /// Size of the content in bytes (UTF-8 for text, PNG bytes for images).
    let byteCount: Int
    /// Present for `.text` items.
    var text: String?
    /// Present for `.image` items; file name inside the images directory.
    var imageFileName: String?
    /// Pixel size for images, used for display.
    var imageWidth: Int?
    var imageHeight: Int?

    static func text(_ string: String) -> ClipItem {
        let data = Data(string.utf8)
        return ClipItem(
            id: UUID(),
            kind: .text,
            createdAt: Date(),
            contentHash: Hashing.sha256Hex(data),
            byteCount: data.count,
            text: string,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil
        )
    }

    static func image(pngData: Data, width: Int, height: Int) -> ClipItem {
        let id = UUID()
        return ClipItem(
            id: id,
            kind: .image,
            createdAt: Date(),
            contentHash: Hashing.sha256Hex(pngData),
            byteCount: pngData.count,
            text: nil,
            imageFileName: "\(id.uuidString).png",
            imageWidth: width,
            imageHeight: height
        )
    }

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
        }
    }

    /// Secondary line: line/character counts for text, dimensions for images.
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
            return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }
}
