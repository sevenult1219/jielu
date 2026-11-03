import Foundation
import LongShotCore

struct SegmentExportResult {
    let directory: URL
    let count: Int
    let segmentHeight: Int
    let overlap: Int
}

enum ImageWriter {
    static func outputDirectory() throws -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = pictures.appendingPathComponent("长截屏", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func saveToPictures(
        _ raw: RawImageFile,
        backingScale: CGFloat,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        let directory = try outputDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let base = "长截屏_\(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(base).png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)_\(suffix).png")
            suffix += 1
        }
        try writePNG(raw, to: url, backingScale: backingScale, progress: progress)
        return url
    }

    static func writePNG(
        _ raw: RawImageFile,
        to url: URL,
        backingScale: CGFloat,
        progress: ((Double) -> Void)? = nil
    ) throws {
        // PNG is lossless and is encoded directly from the raw BGRA rows with a
        // streaming zlib writer. No Core Graphics resampling or JPEG pass is
        // involved, so text and image pixels remain bit-for-bit intact.
        try PNGEncoder.encode(
            raw: raw,
            to: url,
            dpi: max(72, 72 * backingScale),
            progress: progress
        )
    }

    /// Split the image into upload-friendly images that keep the original width.
    /// ChatGPT and similar services scale an image so its longest side is about
    /// 2047 px; a 2816 x 62108 screenshot would become only 92 px wide as a
    /// single file. Segments stay around 2000 px tall with a small overlap so
    /// every line remains readable and no line is lost at a boundary.
    static func exportSegments(
        _ raw: RawImageFile,
        sourceURL: URL?,
        parentDirectory: URL? = nil,
        backingScale: CGFloat,
        maxSegmentHeight: Int = 2_000,
        overlap: Int = 120,
        progress: ((Double, Int) -> Void)? = nil
    ) throws -> SegmentExportResult {
        let height = max(200, maxSegmentHeight)
        let overlapRows = min(max(0, overlap), height / 3)
        let step = max(1, height - overlapRows)
        let directory = try uniqueSegmentDirectory(
            for: sourceURL,
            parentDirectory: parentDirectory
        )
        var count = 0
        do {
            var start = 0
            while start < raw.height {
                let rowCount = min(height, raw.height - start)
                count += 1
                let name = String(format: "%02d.png", count)
                let output = directory.appendingPathComponent(name)
                try PNGEncoder.encodeSegment(
                    raw: raw,
                    startRow: start,
                    rowCount: rowCount,
                    to: output,
                    dpi: max(72, 72 * backingScale)
                )
                progress?(Double(start + rowCount) / Double(raw.height), count)
                if rowCount < height { break }
                start += step
            }
            return SegmentExportResult(
                directory: directory,
                count: count,
                segmentHeight: height,
                overlap: overlapRows
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func uniqueSegmentDirectory(
        for sourceURL: URL?,
        parentDirectory: URL?
    ) throws -> URL {
        let baseName: String
        if let sourceURL {
            baseName = sourceURL.deletingPathExtension().lastPathComponent
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            baseName = "长截屏_\(formatter.string(from: Date()))"
        }
        let baseDirectory: URL
        if let parentDirectory {
            baseDirectory = parentDirectory
        } else if let sourceURL {
            baseDirectory = sourceURL.deletingLastPathComponent()
        } else {
            baseDirectory = try outputDirectory()
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        var directory = baseDirectory.appendingPathComponent("\(baseName)_上传分段", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.path) {
            directory = baseDirectory.appendingPathComponent(
                "\(baseName)_上传分段_\(suffix)",
                isDirectory: true
            )
            suffix += 1
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
