import CoreGraphics
import Foundation

/// A raw BGRA image stored on disk. The pixel data is never resampled; Core
/// Graphics reads it through a file-backed data provider, so arbitrarily tall
/// images do not need to fit in RAM.
public final class RawImageFile {
    public let url: URL
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let ownsFile: Bool

    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var imageCreationFailed = false

    public init(url: URL, width: Int, height: Int, ownsFile: Bool = true) throws {
        guard width > 0, height > 0 else { throw BitmapError.invalidSize }
        self.url = url
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.ownsFile = ownsFile

        let expected = Int64(bytesPerRow) * Int64(height)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let actual = (attributes?[.size] as? NSNumber)?.int64Value, actual < expected {
            throw CanvasError.fileError("临时图像文件不完整。")
        }
    }

    deinit {
        if ownsFile {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public var byteSize: Int64 {
        Int64(bytesPerRow) * Int64(height)
    }

    /// The full-resolution image. The provider is file-backed; simply creating
    /// the CGImage does not decode the whole image.
    public func cgImage() throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage { return cachedImage }
        if imageCreationFailed { throw BitmapError.invalidImage }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(url: url as CFURL) else {
            imageCreationFailed = true
            throw BitmapError.invalidImage
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            imageCreationFailed = true
            throw BitmapError.invalidImage
        }
        cachedImage = image
        return image
    }

    /// A cheap sub-image for the visible part of the tiled preview. `rect` uses
    /// pixel coordinates with the origin at the top-left.
    public func tile(x: Int, y: Int, width tileWidth: Int, height tileHeight: Int) throws -> CGImage? {
        let image = try cgImage()
        let x0 = max(0, min(width - 1, x))
        let y0 = max(0, min(height - 1, y))
        let x1 = max(x0 + 1, min(width, x + tileWidth))
        let y1 = max(y0 + 1, min(height, y + tileHeight))
        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        return image.cropping(to: rect)
    }

    public static func defaultDirectory() throws -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = applicationSupport
            .appendingPathComponent("com.seven.longshot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Remove raw files left behind by a crash or force quit, without touching
    /// a capture that may still belong to a running instance.
    public static func cleanupStaleTemporaryFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        guard let directory = try? defaultDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files where file.pathExtension == "raw" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public static func cleanupAllTemporaryFiles() {
        guard let directory = try? defaultDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return }
        for file in files where file.pathExtension == "raw" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
