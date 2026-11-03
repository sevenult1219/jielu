import CoreGraphics
import XCTest
@testable import LongShotCore

final class OrientationTest: XCTestCase {
    func testBitmapOrientation() throws {
        let image = try BGRAImage(width: 10, height: 10)
        for y in 0..<10 {
            for x in 0..<10 {
                let i = (y * 10 + x) * 4
                let top = y < 5
                image.storage[i] = top ? 0 : 255
                image.storage[i + 1] = 0
                image.storage[i + 2] = top ? 255 : 0
                image.storage[i + 3] = 255
            }
        }
        let gray = image.fullGray()
        XCTAssertNotEqual(gray.pixels[0], gray.pixels[99])
        let cg = try image.makeCGImage()
        let round = try BGRAImage(cgImage: cg)
        let roundGray = round.fullGray()
        XCTAssertEqual(roundGray.pixels[0], gray.pixels[0])
        XCTAssertEqual(roundGray.pixels[99], gray.pixels[99])
        XCTAssertEqual(round.storage[2], 255)
        XCTAssertEqual(round.storage[360 + 2], 0)
    }
}
