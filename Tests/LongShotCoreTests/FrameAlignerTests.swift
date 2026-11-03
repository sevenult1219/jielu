import CoreGraphics
import XCTest
@testable import LongShotCore

final class FrameAlignerTests: XCTestCase {
    private let documentWidth = 420
    private let frameHeight = 760
    private let headerHeight = 64
    private let documentHeight = 7_600

    func testExactOffsetWithStickyHeader() throws {
        let document = makeDocument(width: documentWidth, height: documentHeight)
        let aligner = FrameAligner()

        var previous = try makeFrame(from: document, offset: 0, headerHeight: headerHeight)
        let expectedSteps = [412, 380, 455]
        var offset = 0
        for step in expectedSteps {
            offset += step
            let next = try makeFrame(from: document, offset: offset, headerHeight: headerHeight)
            let result = try aligner.align(previous: previous, next: next)
            XCTAssertEqual(result.offset, step, "alignment should be pixel exact")
            XCTAssertGreaterThan(result.confidence, 0.1)
            previous = next
        }
    }

    func testRetinaSizedFramesAlignAtPixelPrecision() throws {
        let document = makeDocument(width: 1_520, height: 8_000)
        let aligner = FrameAligner()
        let previous = try makeFrame(
            from: document,
            offset: 0,
            headerHeight: 120,
            frameHeightOverride: 1_504
        )
        let next = try makeFrame(
            from: document,
            offset: 676,
            headerHeight: 120,
            frameHeightOverride: 1_504
        )
        let result = try aligner.align(previous: previous, next: next)
        XCTAssertEqual(result.offset, 676)
        XCTAssertEqual(result.overlap, 1_504 - 676)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testStaticFramesReportNoMovement() throws {
        let document = makeDocument(width: documentWidth, height: documentHeight)
        let frame = try makeFrame(from: document, offset: 0, headerHeight: headerHeight)
        let result = try FrameAligner().align(previous: frame, next: frame)
        XCTAssertEqual(result.offset, 0)
        XCTAssertEqual(result.confidence, 1)
    }

    func testCanvasProducesSeamlessLongImage() throws {
        let document = makeDocument(width: documentWidth, height: documentHeight)
        let aligner = FrameAligner()
        let first = try makeFrame(from: document, offset: 0, headerHeight: headerHeight)
        let canvas = try StitchCanvas(first: first)

        var previous = first
        var documentOffset = 0
        let steps = [420, 420, 420, 420]
        for step in steps {
            documentOffset += step
            let next = try makeFrame(from: document, offset: documentOffset, headerHeight: headerHeight)
            let alignment = try aligner.align(previous: previous, next: next)
            XCTAssertEqual(alignment.offset, step)
            try canvas.append(next, offset: alignment.offset)
            previous = next
        }

        XCTAssertEqual(canvas.height, frameHeight + 420 * steps.count)
        let raw = try canvas.finalize()
        let stitched = try BGRAImage(cgImage: raw.cgImage())
        XCTAssertEqual(stitched.width, documentWidth)
        XCTAssertEqual(stitched.height, raw.height)

        // Everything below the sticky header must match the source document.
        var mismatches = 0
        for y in headerHeight..<stitched.height {
            for x in 0..<documentWidth {
                let index = (y * documentWidth + x) * 4
                if stitched.storage[index] != document.storage[index]
                    || stitched.storage[index + 1] != document.storage[index + 1]
                    || stitched.storage[index + 2] != document.storage[index + 2] {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "stitched content should be pixel-identical below the header")
    }

    func testCanvasHasNoFixedHeightLimit() throws {
        let document = makeDocument(width: 240, height: 12_000)
        let first = try makeFrame(
            from: document,
            offset: 0,
            headerHeight: 40,
            frameHeightOverride: 760
        )
        let canvas = try StitchCanvas(first: first)
        var offset = 0
        for _ in 0..<12 {
            offset += 650
            let next = try makeFrame(
                from: document,
                offset: offset,
                headerHeight: 40,
                frameHeightOverride: 760
            )
            try canvas.append(next, offset: 650)
        }
        XCTAssertEqual(canvas.height, 760 + 650 * 12)
        let raw = try canvas.finalize()
        XCTAssertEqual(raw.height, 760 + 650 * 12)
        XCTAssertEqual(raw.width, 240)

        // Verify one row near the very end of the long canvas.
        let stitched = try BGRAImage(cgImage: raw.cgImage())
        let y = stitched.height - 1
        for x in 0..<document.width {
            let index = (y * document.width + x) * 4
            XCTAssertEqual(stitched.storage[index], document.storage[index])
            XCTAssertEqual(stitched.storage[index + 1], document.storage[index + 1])
            XCTAssertEqual(stitched.storage[index + 2], document.storage[index + 2])
        }
    }

    func testAmbiguousBlankFramesDoNotCrash() throws {
        let blank = try BGRAImage(width: 400, height: 700)
        // Opaque light gray, with a little noise so it is not treated as identical.
        for y in 0..<blank.height {
            for x in 0..<blank.width {
                let index = (y * blank.width + x) * 4
                let value = UInt8((x + y) % 5)
                blank.storage[index] = value
                blank.storage[index + 1] = value
                blank.storage[index + 2] = value
                blank.storage[index + 3] = 255
            }
        }
        var second = try BGRAImage(width: 400, height: 700)
        blank.copyRows(
            from: 0,
            count: 700,
            into: second.storage
        )
        second = try BGRAImage(cgImage: second.makeCGImage())
        XCTAssertNoThrow(try FrameAligner().align(previous: blank, next: second))
    }

    // MARK: - Fixtures

    private func makeDocument(width: Int, height: Int) -> BGRAImage {
        // swiftlint:disable:next force_try
        let image = try! BGRAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var r = 248, g = 249, b = 251
                // Text-like horizontal runs with varied lengths.
                if y % 34 > 10 && y % 34 < 22 && x > 24 && x < width - 28 {
                    let seed = (y / 34) * 37 + x / 17
                    if seed % 7 != 0 {
                        r = 40 + (seed % 60)
                        g = 48 + (seed % 40)
                        b = 62 + (seed % 30)
                    }
                }
                // Occasional colored cards.
                let blockY = y / 260
                let blockX = x / 130
                if (blockY + blockX) % 5 == 2 && y % 260 > 40 && y % 260 < 190
                    && x % 130 > 15 && x % 130 < 115 {
                    r = 225 - (blockY % 4) * 18
                    g = 235 - (blockX % 3) * 12
                    b = 250
                }
                let index = (y * width + x) * 4
                image.storage[index] = UInt8(b)
                image.storage[index + 1] = UInt8(g)
                image.storage[index + 2] = UInt8(r)
                image.storage[index + 3] = 255
            }
        }
        return image
    }

    private func makeFrame(
        from document: BGRAImage,
        offset: Int,
        headerHeight: Int,
        frameHeightOverride: Int? = nil
    ) throws -> BGRAImage {
        let height = frameHeightOverride ?? frameHeight
        let frame = try BGRAImage(width: document.width, height: height)
        document.copyRows(from: offset, count: height, into: frame.storage)
        // A fixed, opaque browser-like toolbar. This changes between different
        // documents but never moves, and must not confuse the alignment.
        for y in 0..<headerHeight {
            for x in 0..<document.width {
                let index = (y * document.width + x) * 4
                frame.storage[index] = 232
                frame.storage[index + 1] = 226
                frame.storage[index + 2] = 220
                frame.storage[index + 3] = 255
            }
        }
        return frame
    }
}
