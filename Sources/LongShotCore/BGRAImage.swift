import CoreGraphics
import Foundation

public enum BitmapError: Error, LocalizedError {
    case invalidSize
    case contextCreationFailed
    case invalidImage

    public var errorDescription: String? {
        switch self {
        case .invalidSize: return "图像尺寸无效。"
        case .contextCreationFailed: return "无法创建图像缓冲区。"
        case .invalidImage: return "无法生成图像。"
        }
    }
}

/// A tightly packed 32-bit BGRA bitmap with premultiplied alpha.
/// Row zero is the top row of the image.
public final class BGRAImage {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    let storage: UnsafeMutablePointer<UInt8>

    private var cachedFullGray: GrayImage?
    private var cachedSampleGray: GrayImage?

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw BitmapError.invalidSize }
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        let count = bytesPerRow * height
        storage = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
    }

    public convenience init(cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        try self.init(width: width, height: height)
        try withUnsafeContext { context in
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    deinit {
        storage.deinitialize(count: bytesPerRow * height)
        storage.deallocate()
    }

    /// Direct access to the premultiplied BGRA bytes, row zero first.
    public func withUnsafeMutableBytes(
        _ body: (UnsafeMutableBufferPointer<UInt8>) throws -> Void
    ) rethrows {
        try body(UnsafeMutableBufferPointer(start: storage, count: bytesPerRow * height))
    }

    private func withUnsafeContext(_ body: (CGContext) throws -> Void) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw BitmapError.contextCreationFailed
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw BitmapError.contextCreationFailed
        }
        try body(context)
        context.flush()
    }

    public func makeCGImage() throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw BitmapError.invalidImage
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let retained = Unmanaged.passRetained(self).toOpaque()
        guard let provider = CGDataProvider(
            dataInfo: retained,
            data: storage,
            size: bytesPerRow * height,
            releaseData: { info, _, _ in
                guard let info else { return }
                Unmanaged<BGRAImage>.fromOpaque(info).release()
            }
        ) else {
            Unmanaged<BGRAImage>.fromOpaque(retained).release()
            throw BitmapError.invalidImage
        }
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
            throw BitmapError.invalidImage
        }
        return image
    }

    /// Copies `count` rows beginning at `sourceRow` in this image into `destination`.
    func rowPointer(_ row: Int) -> UnsafePointer<UInt8> {
        precondition(row >= 0 && row < height)
        return UnsafePointer(storage.advanced(by: row * bytesPerRow))
    }

    func copyRows(from sourceRow: Int, count: Int, into destination: UnsafeMutablePointer<UInt8>) {
        precondition(sourceRow >= 0 && count >= 0 && sourceRow + count <= height)
        let source = storage.advanced(by: sourceRow * bytesPerRow)
        destination.update(from: source, count: count * bytesPerRow)
    }

    func copyInto(destination: UnsafeMutablePointer<UInt8>, rowOffset: Int) {
        destination.advanced(by: rowOffset * bytesPerRow)
            .update(from: storage, count: height * bytesPerRow)
    }

    // MARK: - Grayscale analysis images

    func fullGray() -> GrayImage {
        if let cachedFullGray { return cachedFullGray }
        let image = GrayImage(cgImage: self, maxWidth: width)
        cachedFullGray = image
        return image
    }

    func sampleGray(maxWidth: Int = 640) -> GrayImage {
        if let cachedSampleGray, cachedSampleGray.width <= maxWidth {
            return cachedSampleGray
        }
        let image = GrayImage(cgImage: self, maxWidth: maxWidth)
        cachedSampleGray = image
        return image
    }

    /// Cheap perceptual comparison used to detect that scrolling has settled
    /// or that the content has reached its end.
    public func isNearlyEqual(to other: BGRAImage, tolerance: Double = 0.0025) -> Bool {
        guard width == other.width, height == other.height else { return false }
        let a = sampleGray(maxWidth: 260)
        let b = other.sampleGray(maxWidth: 260)
        return a.isNearlyEqual(to: b, tolerance: tolerance)
    }
}

struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(cgImage: BGRAImage, maxWidth: Int) {
        let targetWidth = max(1, min(maxWidth, cgImage.width))
        // Keep the original height. Vertical alignment must remain exact; a
        // proportional downscale introduces half-pixel blur and can make
        // repeating text rows look like a better match than the true offset.
        let targetHeight = cgImage.height
        width = targetWidth
        height = targetHeight

        var buffer = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(
                cgImage.cgImageForDrawing,
                in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            )
            context.flush()
        }
        pixels = buffer
    }

    func isNearlyEqual(to other: GrayImage, tolerance: Double) -> Bool {
        guard width == other.width, height == other.height else { return false }
        let xStep = max(1, width / 320)
        let yStep = max(1, height / 320)
        var total = 0
        var count = 0
        pixels.withUnsafeBufferPointer { a in
            other.pixels.withUnsafeBufferPointer { b in
                var y = 0
                while y < height {
                    var x = 0
                    while x < width {
                        let index = y * width + x
                        total += abs(Int(a[index]) - Int(b[index]))
                        count += 1
                        x += xStep
                    }
                    y += yStep
                }
            }
        }
        return count > 0 && Double(total) / Double(count) / 255.0 <= tolerance
    }
}

private extension BGRAImage {
    /// A CGImage view over the same storage, used only while drawing into a
    /// short-lived grayscale bitmap context.
    var cgImageForDrawing: CGImage {
        // swiftlint:disable:next force_try
        try! makeCGImage()
    }
}
