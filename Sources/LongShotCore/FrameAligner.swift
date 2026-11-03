import Foundation

public struct AlignmentResult: Equatable, Sendable {
    /// Number of pixels the page moved upwards between the two frames.
    public let offset: Int
    /// Height of the shared region, in pixels.
    public let overlap: Int
    /// Mean absolute grayscale error in the shared region (0...1, lower is better).
    public let score: Double
    /// How clearly the winning offset beat the next plausible offset (0...1).
    public let confidence: Double

    public var didMove: Bool { offset > 0 }
}

public enum AlignmentError: Error, LocalizedError, Equatable {
    case sizeMismatch
    case notEnoughOverlap
    case ambiguous

    public var errorDescription: String? {
        switch self {
        case .sizeMismatch:
            return "前后两帧的尺寸不一致。"
        case .notEnoughOverlap:
            return "页面滚动幅度过大，两帧之间没有足够的重叠区域。"
        case .ambiguous:
            return "无法可靠识别滚动位置，页面可能包含动画或大面积重复内容。"
        }
    }
}

/// Finds the vertical translation between consecutive window captures.
///
/// The matcher ignores the top of the frame (where toolbars and sticky headers
/// live), the extreme edges (scroll bars), and then refines the coarse result at
/// full resolution so stitches remain pixel-exact.
public struct FrameAligner {
    public var maximumScrollFraction: Double
    public var minimumOffset: Int

    public init(maximumScrollFraction: Double = 0.60, minimumOffset: Int = 3) {
        self.maximumScrollFraction = maximumScrollFraction
        self.minimumOffset = minimumOffset
    }

    public func align(previous: BGRAImage, next: BGRAImage) throws -> AlignmentResult {
        guard previous.width == next.width, previous.height == next.height else {
            throw AlignmentError.sizeMismatch
        }
        guard previous.width > 20, previous.height > 40 else {
            throw AlignmentError.sizeMismatch
        }

        let previousGray = previous.fullGray()
        let nextGray = next.fullGray()
        let previousSample = previous.sampleGray(maxWidth: 640)
        let nextSample = next.sampleGray(maxWidth: 640)

        if previousSample.isNearlyEqual(to: nextSample, tolerance: 0.0008) {
            return AlignmentResult(offset: 0, overlap: previous.height, score: 0, confidence: 1)
        }

        let coarseCandidates = try coarseCandidates(previous: previousSample, next: nextSample)
        let scale = Double(previous.height) / Double(previousSample.height)
        let maximumOffset = max(
            minimumOffset + 1,
            Int(Double(previous.height) * maximumScrollFraction)
        )

        var refined: [Candidate] = []
        for candidate in coarseCandidates {
            let approximate = Int((Double(candidate.offset) * scale).rounded())
            let radius = max(4, Int((scale * 3).rounded()) + 1)
            let lower = max(minimumOffset, approximate - radius)
            let upper = min(maximumOffset, approximate + radius)
            guard lower <= upper else { continue }
            for offset in lower...upper {
                let value = score(
                    offset: offset,
                    previous: previousGray,
                    next: nextGray,
                    probeFractions: [0.20, 0.31, 0.42],
                    bandFraction: 0.025,
                    horizontalRange: 0.035...0.945,
                    columnStep: max(1, previous.width / 760)
                )
                guard value.count > 0 else { continue }
                refined.append(Candidate(offset: offset, score: value.score))
            }
        }

        guard let best = refined.min(by: { $0.score < $1.score }) else {
            throw AlignmentError.notEnoughOverlap
        }
        if best.offset <= 2 {
            return AlignmentResult(offset: 0, overlap: previous.height, score: best.score, confidence: 0)
        }

        let lastVisible = Double(previous.height - best.offset) / Double(previous.height) - 0.018
        let verificationStart = 0.17
        let verificationEnd = min(0.90, max(verificationStart + 0.02, lastVisible))
        var verificationFractions: [Double] = []
        for index in 0..<6 {
            verificationFractions.append(
                verificationStart + (verificationEnd - verificationStart) * Double(index) / 5
            )
        }
        let verification = score(
            offset: best.offset,
            previous: previousGray,
            next: nextGray,
            probeFractions: verificationFractions,
            bandFraction: 0.012,
            horizontalRange: 0.035...0.945,
            columnStep: max(1, previous.width / 420)
        )

        let minimumSeparation = max(12, previous.height / 90)
        var alternative = Double.infinity
        for candidate in refined where abs(candidate.offset - best.offset) >= minimumSeparation {
            alternative = min(alternative, candidate.score)
        }
        for delta in [10, 18, 30, 52, 84] {
            for direction in [-1, 1] {
                let offset = best.offset + delta * direction
                guard offset >= minimumOffset, offset <= maximumOffset else { continue }
                let value = score(
                    offset: offset,
                    previous: previousGray,
                    next: nextGray,
                    probeFractions: [0.20, 0.31, 0.42],
                    bandFraction: 0.025,
                    horizontalRange: 0.035...0.945,
                    columnStep: max(2, previous.width / 500)
                )
                if value.count > 0 { alternative = min(alternative, value.score) }
            }
        }

        if alternative.isFinite {
            let separation = alternative - best.score
            let confidence = max(0, min(1, separation / max(alternative, 0.000_001)))
            if confidence < 0.10 && best.score > 0.0045 {
                throw AlignmentError.ambiguous
            }
            if verification.score > 0.080 || best.score > 0.060 {
                throw AlignmentError.ambiguous
            }
            return AlignmentResult(
                offset: best.offset,
                overlap: previous.height - best.offset,
                score: max(best.score, verification.score),
                confidence: confidence
            )
        }

        if verification.score > 0.080 || best.score > 0.060 {
            throw AlignmentError.ambiguous
        }
        // A single excellent match is acceptable; a weak one is not.
        if best.score > 0.008 {
            throw AlignmentError.ambiguous
        }
        return AlignmentResult(
            offset: best.offset,
            overlap: previous.height - best.offset,
            score: best.score,
            confidence: 1
        )
    }

    // MARK: - Coarse search

    private struct Candidate {
        let offset: Int
        let score: Double
    }

    private func coarseCandidates(previous: GrayImage, next: GrayImage) throws -> [Candidate] {
        let height = previous.height
        let maximumOffset = Int(Double(height) * maximumScrollFraction)
        guard maximumOffset > minimumOffset + 1 else {
            throw AlignmentError.notEnoughOverlap
        }

        var scores: [Candidate] = []
        scores.reserveCapacity(maximumOffset + 1)

        for offset in minimumOffset...maximumOffset {
            let value = score(
                offset: offset,
                previous: previous,
                next: next,
                probeFractions: [0.20, 0.31, 0.42],
                bandFraction: 0.025,
                horizontalRange: 0.035...0.945,
                columnStep: 1
            )
            if value.count > 0 {
                scores.append(Candidate(offset: offset, score: value.score))
            }
        }
        guard let best = scores.min(by: { $0.score < $1.score }) else {
            throw AlignmentError.notEnoughOverlap
        }
        guard best.score < 0.20 else { throw AlignmentError.ambiguous }

        var selected: [Candidate] = []
        let suppression = max(3, height / 40)
        var remaining = scores
        for _ in 0..<7 {
            guard let candidate = remaining.min(by: { $0.score < $1.score }) else { break }
            selected.append(candidate)
            remaining.removeAll { abs($0.offset - candidate.offset) <= suppression }
        }
        return selected
    }

    private func score(
        offset: Int,
        previous: GrayImage,
        next: GrayImage,
        probeFractions: [Double],
        bandFraction: Double,
        horizontalRange: ClosedRange<Double>,
        columnStep: Int
    ) -> (score: Double, count: Int) {
        let width = previous.width
        let height = previous.height
        guard width == next.width, height == next.height else { return (1, 0) }

        let xStart = max(1, Int(Double(width) * horizontalRange.lowerBound))
        let xEnd = min(width - 2, Int(Double(width) * horizontalRange.upperBound))
        guard xEnd > xStart else { return (1, 0) }

        let bandHeight = max(2, Int(Double(height) * bandFraction))
        var total = 0
        var count = 0

        previous.pixels.withUnsafeBufferPointer { previousBuffer in
            next.pixels.withUnsafeBufferPointer { nextBuffer in
                guard let p = previousBuffer.baseAddress,
                      let n = nextBuffer.baseAddress else { return }

                for fraction in probeFractions {
                    let nextRow = Int(Double(height) * fraction)
                    let previousRow = nextRow + offset
                    guard previousRow >= 0,
                          nextRow + bandHeight <= height,
                          previousRow + bandHeight <= height else { continue }

                    for row in 0..<bandHeight {
                        let pBase = (previousRow + row) * width
                        let nBase = (nextRow + row) * width
                        var x = xStart
                        while x < xEnd {
                            total += abs(Int(p[pBase + x]) - Int(n[nBase + x]))
                            count += 1
                            x += columnStep
                        }
                    }
                }
            }
        }

        guard count > 0 else { return (1, 0) }
        return (Double(total) / Double(count) / 255.0, count)
    }
}
