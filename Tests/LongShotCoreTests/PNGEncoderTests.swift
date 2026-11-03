import CoreGraphics
import ImageIO
import XCTest
@testable import LongShotCore

final class PNGEncoderTests: XCTestCase {
    func testPNGIsPixelIdenticalToRawCanvas() throws {
        let width = 360
        let documentHeight = 6_000
        let frameHeight = 640
        let document = makeSharpDocument(width: width, height: documentHeight)

        let first = try makeFrame(from: document, offset: 0, height: frameHeight)
        let canvas = try StitchCanvas(first: first)
        var offset = 0
        for _ in 0..<8 {
            offset += 520
            let next = try makeFrame(from: document, offset: offset, height: frameHeight)
            try canvas.append(next, offset: 520)
        }
        let raw = try canvas.finalize()

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("longshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try PNGEncoder.encode(raw: raw, to: output, dpi: 144)

        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("PNG could not be decoded")
        }
        XCTAssertEqual(image.width, raw.width)
        XCTAssertEqual(image.height, raw.height)

        let decoded = try BGRAImage(cgImage: image)
        let original = try BGRAImage(cgImage: raw.cgImage())
        XCTAssertEqual(decoded.width, raw.width)
        XCTAssertEqual(decoded.height, raw.height)

        var mismatches = 0
        for y in 0..<decoded.height {
            for x in 0..<decoded.width {
                let index = (y * decoded.width + x) * 4
                if decoded.storage[index] != original.storage[index]
                    || decoded.storage[index + 1] != original.storage[index + 1]
                    || decoded.storage[index + 2] != original.storage[index + 2]
                    || decoded.storage[index + 3] != 255 {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "PNG must preserve every pixel exactly")
    }

    func testPNGSegmentKeepsFullWidthAndExactRows() throws {
        let width = 360
        let height = 2_000
        let image = try BGRAImage(width: width, height: height)
        image.withUnsafeMutableBytes { buffer in
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    buffer[i] = UInt8((y / 3) % 256)
                    buffer[i + 1] = UInt8(x % 256)
                    buffer[i + 2] = UInt8((x * 7 + y) % 256)
                    buffer[i + 3] = 255
                }
            }
        }
        let canvas = try StitchCanvas(first: image)
        let raw = try canvas.finalize()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("longshot-segment-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try PNGEncoder.encodeSegment(raw: raw, startRow: 700, rowCount: 600, to: output, dpi: 144)

        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let decodedImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("segment could not be decoded")
        }
        XCTAssertEqual(decodedImage.width, width)
        XCTAssertEqual(decodedImage.height, 600)
        let decoded = try BGRAImage(cgImage: decodedImage)
        let original = try BGRAImage(cgImage: raw.cgImage())
        var mismatches = 0
        for y in 0..<600 {
            for x in 0..<width {
                let d = (y * width + x) * 4
                let o = ((y + 700) * width + x) * 4
                if decoded.storage[d] != original.storage[o]
                    || decoded.storage[d + 1] != original.storage[o + 1]
                    || decoded.storage[d + 2] != original.storage[o + 2] {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testPNGHasExpectedDimensionsAndDPI() throws {
        let width = 320
        let height = 2_000
        let image = try BGRAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                image.storage[i] = UInt8(x % 256)
                image.storage[i + 1] = UInt8(y % 256)
                image.storage[i + 2] = UInt8((x + y) % 256)
                image.storage[i + 3] = 255
            }
        }
        let canvas = try StitchCanvas(first: image)
        let raw = try canvas.finalize()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("longshot-dpi-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try PNGEncoder.encode(raw: raw, to: output, dpi: 144)
        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("missing properties")
        }
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, width)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, height)
        XCTAssertEqual(properties[kCGImagePropertyDPIWidth] as? Double, 144)
    }

    // MARK: - Fixtures

    private func makeSharpDocument(width: Int, height: Int) -> BGRAImage {
        // swiftlint:disable:next force_try
        let image = try! BGRAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var r = 250, g = 250, b = 250
                // One-pixel checkerboard: any resampling would visibly change it.
                if y >= 100 && y < 180 && x < 180 {
                    let on = (x + y) % 2 == 0
                    r = on ? 0 : 255
                    g = on ? 0 : 255
                    b = on ? 0 : 255
                }
                // Thin text-like strokes.
                if y % 29 > 12 && y % 29 < 15 && x > 28 && x < width - 30 {
                    r = 18; g = 22; b = 30
                }
                if y % 97 > 40 && y % 97 < 44 && x > 60 && x < width - 80 {
                    r = 220; g = 40; b = 60
                }
                let i = (y * width + x) * 4
                image.storage[i] = UInt8(b)
                image.storage[i + 1] = UInt8(g)
                image.storage[i + 2] = UInt8(r)
                image.storage[i + 3] = 255
            }
        }
        return image
    }

    private func makeFrame(from document: BGRAImage, offset: Int, height: Int) throws -> BGRAImage {
        let frame = try BGRAImage(width: document.width, height: height)
        document.copyRows(from: offset, count: height, into: frame.storage)
        return frame
    }
}
