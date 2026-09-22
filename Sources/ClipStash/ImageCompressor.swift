import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Optionally re-encodes large, fully opaque images as JPEG to save disk space.
///
/// Only used when the "Convert large images to JPEG" setting is on. Images
/// that are already JPEG, smaller than the threshold, or that contain any
/// transparency are left exactly as copied.
enum ImageCompressor {
    /// Images at or below this size are never touched.
    static let sizeThreshold = 1_000_000
    static let jpegQuality: CGFloat = 0.85

    static func compressIfWorthwhile(_ payload: ClipboardMonitor.ImagePayload) -> ClipboardMonitor.ImagePayload {
        guard payload.fileExtension != "jpg", payload.data.count > sizeThreshold else { return payload }
        guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              isOpaque(image),
              let jpeg = encodeJPEG(image),
              jpeg.count < payload.data.count else { return payload }
        return ClipboardMonitor.ImagePayload(data: jpeg, fileExtension: "jpg", width: payload.width, height: payload.height)
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// True when the image has no alpha channel, or has one but every pixel
    /// is fully opaque. The pixel check runs on a downsampled copy so very
    /// large photos are cheap to inspect.
    private static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            break
        }

        let maxSide = 1024
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }

        var index = 3
        while index < pixels.count {
            if pixels[index] != 255 { return false }
            index += 4
        }
        return true
    }
}
