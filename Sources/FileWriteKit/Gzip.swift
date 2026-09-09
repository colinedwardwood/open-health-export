import CZlib
import Foundation

public enum GzipError: Error, Equatable {
    case deflate
    case inflate
}

/// Deterministic gzip at zlib level 1 (NFR-16). OS/mtime bytes come from zlib defaults;
/// the deflate stream is what receivers gunzip.
public enum Gzip {
    public static func compress(_ data: Data) throws -> Data {
        try transcode(data, compressing: true)
    }

    public static func decompress(_ data: Data) throws -> Data {
        try transcode(data, compressing: false)
    }

    private static func transcode(_ data: Data, compressing: Bool) throws -> Data {
        var stream = z_stream()
        let windowBits: Int32 = 15 + 16
        let initStatus: Int32 = compressing
            ? deflateInit2_(
                &stream,
                Z_BEST_SPEED,
                Z_DEFLATED,
                windowBits,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            : inflateInit2_(
                &stream,
                windowBits,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        guard initStatus == Z_OK else {
            throw compressing ? GzipError.deflate : GzipError.inflate
        }
        defer {
            if compressing {
                _ = deflateEnd(&stream)
            } else {
                _ = inflateEnd(&stream)
            }
        }

        var output = Data()
        let chunk = 16_384
        func pull(_ flush: Int32) throws -> Int32 {
            var buffer = [UInt8](repeating: 0, count: chunk)
            let status = buffer.withUnsafeMutableBytes { dst -> Int32 in
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(dst.count)
                return compressing ? deflate(&stream, flush) : inflate(&stream, flush)
            }
            output.append(contentsOf: buffer.prefix(chunk - Int(stream.avail_out)))
            return status
        }

        if data.isEmpty {
            stream.avail_in = 0
            stream.next_in = nil
            let status = try pull(Z_FINISH)
            guard status == Z_STREAM_END else {
                throw compressing ? GzipError.deflate : GzipError.inflate
            }
            return output
        }

        return try data.withUnsafeBytes { src -> Data in
            let base = src.bindMemory(to: Bytef.self).baseAddress
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(src.count)
            var status: Int32
            repeat {
                status = try pull(Z_FINISH)
                if status == Z_STREAM_END { break }
                if status != Z_OK { throw compressing ? GzipError.deflate : GzipError.inflate }
            } while stream.avail_out == 0
            guard status == Z_STREAM_END else {
                throw compressing ? GzipError.deflate : GzipError.inflate
            }
            return output
        }
    }
}
