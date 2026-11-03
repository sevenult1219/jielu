import CoreGraphics
import Darwin
import Foundation
import zlib

public enum PNGEncoderError: Error, LocalizedError {
    case invalidDimensions
    case fileError(String)
    case compressionFailed(Int32)
    case readFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: return "图像尺寸超出 PNG 格式允许的范围。"
        case .fileError(let message): return message
        case .compressionFailed(let code): return "PNG 压缩失败（zlib \(code)）。"
        case .readFailed: return "读取临时图像失败。"
        case .writeFailed: return "写入 PNG 文件失败。"
        }
    }
}

/// A streaming, lossless PNG encoder. It reads the raw BGRA file one block at a
/// time and writes the compressed IDAT stream incrementally, so peak memory is
/// independent of the final image height. Pixels are copied 1:1 and never
/// resampled.
public enum PNGEncoder {
    public static func encode(
        raw: RawImageFile,
        to url: URL,
        dpi: Double = 144,
        compressionLevel: Int32 = 4,
        progress: ((Double) -> Void)? = nil
    ) throws {
        try encodeRegion(
            raw: raw,
            startRow: 0,
            rowCount: raw.height,
            to: url,
            dpi: dpi,
            compressionLevel: compressionLevel,
            progress: progress
        )
    }

    /// Encodes a vertical slice while keeping the full original width. Used for
    /// upload-friendly segments (for example, ChatGPT's 2047 px long-side cap).
    public static func encodeSegment(
        raw: RawImageFile,
        startRow: Int,
        rowCount: Int,
        to url: URL,
        dpi: Double = 144,
        compressionLevel: Int32 = 4,
        progress: ((Double) -> Void)? = nil
    ) throws {
        guard startRow >= 0, rowCount > 0, startRow + rowCount <= raw.height else {
            throw PNGEncoderError.invalidDimensions
        }
        try encodeRegion(
            raw: raw,
            startRow: startRow,
            rowCount: rowCount,
            to: url,
            dpi: dpi,
            compressionLevel: compressionLevel,
            progress: progress
        )
    }

    private static func encodeRegion(
        raw: RawImageFile,
        startRow: Int,
        rowCount: Int,
        to url: URL,
        dpi: Double,
        compressionLevel: Int32,
        progress: ((Double) -> Void)?
    ) throws {
        guard raw.width > 0, rowCount > 0,
              raw.width <= Int(UInt32.max), rowCount <= Int(UInt32.max) else {
            throw PNGEncoderError.invalidDimensions
        }

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".longshot-\(UUID().uuidString).png.part")
        let outputFD = open(temporaryURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard outputFD >= 0 else {
            throw PNGEncoderError.fileError("无法创建 PNG 文件：\(String(cString: strerror(errno)))")
        }
        _ = fchmod(outputFD, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

        var success = false
        var outputClosed = false
        defer {
            if !outputClosed { close(outputFD) }
            if !success { unlink(temporaryURL.path) }
        }

        let inputFD = open(raw.url.path, O_RDONLY)
        guard inputFD >= 0 else {
            throw PNGEncoderError.fileError("无法读取临时图像文件。")
        }
        defer { close(inputFD) }
        if startRow > 0 {
            guard lseek(inputFD, off_t(startRow) * off_t(raw.bytesPerRow), SEEK_SET) >= 0 else {
                throw PNGEncoderError.fileError("无法定位到分段起始行。")
            }
        }

        try writeAll(fd: outputFD, bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr: [UInt8] = []
        ihdr.append(contentsOf: bigEndian(UInt32(raw.width)))
        ihdr.append(contentsOf: bigEndian(UInt32(rowCount)))
        ihdr.append(8)   // bit depth
        ihdr.append(6)   // RGBA
        ihdr.append(0)   // deflate
        ihdr.append(0)   // adaptive filtering
        ihdr.append(0)   // no interlace
        try writeChunk(fd: outputFD, type: "IHDR", data: ihdr)

        if dpi > 0 {
            let pixelsPerMeter = UInt32((dpi / 0.0254).rounded())
            var phys: [UInt8] = []
            phys.append(contentsOf: bigEndian(pixelsPerMeter))
            phys.append(contentsOf: bigEndian(pixelsPerMeter))
            phys.append(1)
            try writeChunk(fd: outputFD, type: "pHYs", data: phys)
        }

        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            compressionLevel,
            Z_DEFLATED,
            15,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            throw PNGEncoderError.compressionFailed(initResult)
        }
        defer { deflateEnd(&stream) }

        let outputCapacity = 1 << 20
        var outputBuffer = [UInt8](repeating: 0, count: outputCapacity)
        outputBuffer.withUnsafeMutableBufferPointer { buffer in
            stream.next_out = buffer.baseAddress
            stream.avail_out = uInt(outputCapacity)
        }

        func emitChunkIfNeeded() throws {
            let produced = outputCapacity - Int(stream.avail_out)
            guard produced > 0 else { return }
            let data = Array(outputBuffer[0..<produced])
            try writeChunk(fd: outputFD, type: "IDAT", data: data)
            outputBuffer.withUnsafeMutableBufferPointer { buffer in
                stream.next_out = buffer.baseAddress
                stream.avail_out = uInt(outputCapacity)
            }
        }

        func feed(_ buffer: UnsafeBufferPointer<UInt8>) throws {
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: base)
            stream.avail_in = uInt(buffer.count)
            while stream.avail_in > 0 {
                if stream.avail_out == 0 {
                    try emitChunkIfNeeded()
                }
                let status = deflate(&stream, Z_NO_FLUSH)
                guard status == Z_OK else {
                    throw PNGEncoderError.compressionFailed(status)
                }
            }
        }

        let rowBytes = raw.bytesPerRow
        let rowsPerBlock = max(1, (8 * 1024 * 1024) / rowBytes)
        var rawBlock = [UInt8](repeating: 0, count: rowsPerBlock * rowBytes)
        var pngRow = [UInt8](repeating: 0, count: rowBytes + 1)
        let progressEvery = max(1, rowCount / 100)
        progress?(0)

        var row = 0
        while row < rowCount {
            let rows = min(rowsPerBlock, rowCount - row)
            try readExact(fd: inputFD, into: &rawBlock, count: rows * rowBytes)

            try rawBlock.withUnsafeBufferPointer { source in
                for localRow in 0..<rows {
                    let sourceRow = source.baseAddress! + localRow * rowBytes
                    pngRow.withUnsafeMutableBufferPointer { destination in
                        destination[0] = 0 // filter: None
                        var index = 0
                        while index < rowBytes {
                            let alpha = sourceRow[index + 3]
                            if alpha == 255 {
                                destination[index + 1] = sourceRow[index + 2]
                                destination[index + 2] = sourceRow[index + 1]
                                destination[index + 3] = sourceRow[index]
                                destination[index + 4] = 255
                            } else if alpha == 0 {
                                destination[index + 1] = 0
                                destination[index + 2] = 0
                                destination[index + 3] = 0
                                destination[index + 4] = 0
                            } else {
                                let a = Int(alpha)
                                destination[index + 1] = UInt8(min(255, (Int(sourceRow[index + 2]) * 255 + a / 2) / a))
                                destination[index + 2] = UInt8(min(255, (Int(sourceRow[index + 1]) * 255 + a / 2) / a))
                                destination[index + 3] = UInt8(min(255, (Int(sourceRow[index]) * 255 + a / 2) / a))
                                destination[index + 4] = alpha
                            }
                            index += 4
                        }
                    }
                    try pngRow.withUnsafeBufferPointer { try feed($0) }
                }
            }

            row += rows
            if row % progressEvery == 0 || row == rowCount {
                progress?(Double(row) / Double(rowCount))
            }
        }

        while true {
            if stream.avail_out == 0 {
                try emitChunkIfNeeded()
            }
            let status = deflate(&stream, Z_FINISH)
            if status == Z_STREAM_END { break }
            guard status == Z_OK else {
                throw PNGEncoderError.compressionFailed(status)
            }
        }
        try emitChunkIfNeeded()
        try writeChunk(fd: outputFD, type: "IEND", data: [])

        let closeResult = close(outputFD)
        outputClosed = true
        guard closeResult == 0 else {
            throw PNGEncoderError.writeFailed
        }
        success = true
        if rename(temporaryURL.path, url.path) != 0 {
            success = false
            throw PNGEncoderError.fileError("无法完成 PNG 文件：\(String(cString: strerror(errno)))")
        }
        progress?(1)
    }

    // MARK: - Binary helpers

    private static func writeChunk(fd: Int32, type: String, data: [UInt8]) throws {
        let typeBytes = Array(type.utf8)
        precondition(typeBytes.count == 4)
        var header: [UInt8] = []
        header.append(contentsOf: bigEndian(UInt32(data.count)))
        header.append(contentsOf: typeBytes)
        try writeAll(fd: fd, bytes: header)
        if !data.isEmpty {
            try writeAll(fd: fd, bytes: data)
        }
        var checksum = crc32(0, nil, 0)
        checksum = typeBytes.withUnsafeBufferPointer {
            crc32(checksum, $0.baseAddress, uInt(typeBytes.count))
        }
        if !data.isEmpty {
            checksum = data.withUnsafeBufferPointer {
                crc32(checksum, $0.baseAddress, uInt(data.count))
            }
        }
        try writeAll(fd: fd, bytes: bigEndian(UInt32(checksum)))
    }

    private static func writeAll(fd: Int32, bytes: [UInt8]) throws {
        try bytes.withUnsafeBufferPointer { buffer in
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(fd, buffer.baseAddress! + written, bytes.count - written)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw PNGEncoderError.fileError("写入 PNG 失败：\(String(cString: strerror(errno)))")
                }
                if result == 0 { throw PNGEncoderError.writeFailed }
                written += result
            }
        }
    }

    private static func readExact(fd: Int32, into buffer: inout [UInt8], count: Int) throws {
        try buffer.withUnsafeMutableBytes { raw in
            var readCount = 0
            while readCount < count {
                let result = Darwin.read(fd, raw.baseAddress! + readCount, count - readCount)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw PNGEncoderError.readFailed
                }
                if result == 0 { throw PNGEncoderError.readFailed }
                readCount += result
            }
        }
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }
}
