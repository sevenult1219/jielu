import CoreGraphics
import Darwin
import Foundation

public enum CanvasError: Error, LocalizedError {
    case sizeMismatch
    case invalidOffset
    case allocationFailed
    case diskFull
    case fileError(String)

    public var errorDescription: String? {
        switch self {
        case .sizeMismatch:
            return "待拼接画面的宽度不一致。"
        case .invalidOffset:
            return "滚动位移无效。"
        case .allocationFailed:
            return "无法创建临时图像文件。"
        case .diskFull:
            return "磁盘剩余空间不足，已停止继续滚动。"
        case .fileError(let message):
            return message
        }
    }
}

/// Appends only the newly revealed rows of each frame to a raw BGRA file.
/// The canvas has no height limit: memory use stays constant and long captures
/// consume disk instead of RAM.
public final class StitchCanvas {
    public let width: Int
    public private(set) var height: Int

    public let fileURL: URL
    public let minimumFreeBytes: Int64
    public private(set) var bytesWritten: Int64 = 0

    private let fileDescriptor: Int32
    private let bytesPerRow: Int
    private let frameHeight: Int
    private let directory: URL
    private var isFinalized = false

    public init(
        first: BGRAImage,
        directory: URL? = nil,
        minimumFreeBytes: Int64 = 1_024 * 1024 * 1024
    ) throws {
        guard first.width > 0, first.height > 0 else { throw CanvasError.invalidOffset }
        width = first.width
        bytesPerRow = first.width * 4
        frameHeight = first.height
        height = first.height
        self.minimumFreeBytes = max(64 * 1024 * 1024, minimumFreeBytes)
        let directory = try directory ?? RawImageFile.defaultDirectory()
        self.directory = directory
        fileURL = directory.appendingPathComponent("capture-\(UUID().uuidString).raw")

        fileDescriptor = open(fileURL.path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw CanvasError.fileError("无法创建临时图像文件：\(String(cString: strerror(errno)))")
        }

        do {
            try ensureFreeSpace(for: Int64(first.height) * Int64(bytesPerRow))
            try writeRows(
                from: first.rowPointer(0),
                byteCount: first.height * bytesPerRow
            )
        } catch {
            close(fileDescriptor)
            unlink(fileURL.path)
            throw error
        }
    }

    deinit {
        if !isFinalized {
            close(fileDescriptor)
            unlink(fileURL.path)
        }
    }

    /// Appends `offset` newly revealed rows from the bottom of `frame`.
    @discardableResult
    public func append(_ frame: BGRAImage, offset: Int) throws -> Int {
        guard !isFinalized else { throw CanvasError.invalidOffset }
        guard frame.width == width, frame.height == frameHeight else {
            throw CanvasError.sizeMismatch
        }
        guard offset > 0, offset < frame.height else {
            throw CanvasError.invalidOffset
        }

        let byteCount = offset * bytesPerRow
        try ensureFreeSpace(for: Int64(byteCount))
        let sourceRow = frame.height - offset
        try writeRows(
            from: frame.rowPointer(sourceRow),
            byteCount: byteCount
        )
        height += offset
        return offset
    }

    /// Flushes the raw file and returns a file-backed image. The caller owns the
    /// returned file; it is deleted when `RawImageFile` is released.
    public func finalize() throws -> RawImageFile {
        guard !isFinalized else { throw CanvasError.invalidOffset }
        isFinalized = true
        let expected = Int64(height) * Int64(bytesPerRow)
        guard ftruncate(fileDescriptor, off_t(expected)) == 0 else {
            close(fileDescriptor)
            unlink(fileURL.path)
            throw CanvasError.fileError("无法完成临时图像文件：\(String(cString: strerror(errno)))")
        }
        guard close(fileDescriptor) == 0 else {
            unlink(fileURL.path)
            throw CanvasError.fileError("无法关闭临时图像文件：\(String(cString: strerror(errno)))")
        }
        do {
            return try RawImageFile(
                url: fileURL,
                width: width,
                height: height,
                ownsFile: true
            )
        } catch {
            unlink(fileURL.path)
            throw error
        }
    }

    public func discard() {
        guard !isFinalized else { return }
        isFinalized = true
        close(fileDescriptor)
        unlink(fileURL.path)
    }

    private func ensureFreeSpace(for byteCount: Int64) throws {
        guard let values = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let free = values.volumeAvailableCapacityForImportantUsage else {
            return
        }
        if free < byteCount + minimumFreeBytes {
            throw CanvasError.diskFull
        }
    }

    private func writeRows(
        from source: UnsafePointer<UInt8>,
        byteCount: Int
    ) throws {
        var written = 0
        while written < byteCount {
            let result = write(
                fileDescriptor,
                source.advanced(by: written),
                byteCount - written
            )
            if result < 0 {
                if errno == EINTR { continue }
                throw CanvasError.fileError("写入临时图像失败：\(String(cString: strerror(errno)))")
            }
            if result == 0 {
                throw CanvasError.fileError("写入临时图像失败：磁盘空间不足。")
            }
            written += result
        }
        bytesWritten += Int64(byteCount)
    }
}
