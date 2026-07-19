import Foundation
import zlib

enum ZipArchiveReader {
    private struct CentralDirectoryInfo {
        var entryCount: UInt64
        var size: UInt64
        var offset: UInt64
    }

    struct Entry {
        var name: String
        var localHeaderOffset: UInt64
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var compressionMethod: UInt16
        var generalPurposeBitFlag: UInt16
        var crc32: UInt32

        var isStored: Bool {
            compressionMethod == 0 && compressedSize == uncompressedSize
        }

        var isDeflated: Bool {
            compressionMethod == 8
        }

        var isReadable: Bool {
            isStored || isDeflated
        }

        var hasUTF8NameFlag: Bool {
            (generalPurposeBitFlag & 0x0800) != 0
        }
    }

    static func entries(in archive: URL) throws -> [Entry] {
        let data = try Data(contentsOf: archive, options: [.mappedIfSafe])
        guard let eocd = endOfCentralDirectoryOffset(in: data) else {
            throw NativeDownloadError.unsupported("ZIP central directory was not found.")
        }

        let directory = try centralDirectoryInfo(eocd: eocd, in: data)
        guard directory.entryCount <= UInt64(Int.max),
              directory.size <= UInt64(Int.max),
              directory.offset <= UInt64(Int.max) else {
            throw NativeDownloadError.unsupported("ZIP central directory exceeds supported limits.")
        }

        let entryCount = Int(directory.entryCount)
        let centralDirectorySize = Int(directory.size)
        let centralDirectoryOffset = Int(directory.offset)
        guard centralDirectoryOffset >= 0,
              centralDirectorySize >= 0,
              centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw NativeDownloadError.unsupported("ZIP central directory is invalid.")
        }

        var entries: [Entry] = []
        var offset = centralDirectoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  try uint32(at: offset, in: data) == 0x02014b50 else {
                throw NativeDownloadError.unsupported("ZIP central directory entry is invalid.")
            }

            let generalPurposeBitFlag = try uint16(at: offset + 8, in: data)
            let compressionMethod = try uint16(at: offset + 10, in: data)
            let crc32 = try uint32(at: offset + 16, in: data)
            let compressedSize = try uint32(at: offset + 20, in: data)
            let uncompressedSize = try uint32(at: offset + 24, in: data)
            let nameLength = Int(try uint16(at: offset + 28, in: data))
            let extraLength = Int(try uint16(at: offset + 30, in: data))
            let commentLength = Int(try uint16(at: offset + 32, in: data))
            let localHeaderOffset = try uint32(at: offset + 42, in: data)
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            let extraStart = nameEnd
            let extraEnd = extraStart + extraLength
            guard nameEnd <= data.count else {
                throw NativeDownloadError.unsupported("ZIP entry name is invalid.")
            }
            guard extraEnd <= data.count else {
                throw NativeDownloadError.unsupported("ZIP entry extra field is invalid.")
            }

            let resolved = try resolvedZIP64EntryFields(
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset,
                extra: data.subdata(in: extraStart..<extraEnd)
            )

            let nameData = data.subdata(in: nameStart..<nameEnd)
            if let name = decodedEntryName(from: nameData, generalPurposeBitFlag: generalPurposeBitFlag),
               isSafeEntryName(name),
               !name.hasSuffix("/") {
                entries.append(Entry(
                    name: name,
                    localHeaderOffset: resolved.localHeaderOffset,
                    compressedSize: resolved.compressedSize,
                    uncompressedSize: resolved.uncompressedSize,
                    compressionMethod: compressionMethod,
                    generalPurposeBitFlag: generalPurposeBitFlag,
                    crc32: crc32
                ))
            }

            offset = nameEnd + extraLength + commentLength
            guard offset <= centralDirectoryOffset + centralDirectorySize else {
                throw NativeDownloadError.unsupported("ZIP central directory entry length is invalid.")
            }
        }

        return entries
    }

    static func data(for entry: Entry, in archive: URL) throws -> Data {
        let data = try Data(contentsOf: archive, options: [.mappedIfSafe])
        return try Self.data(for: entry, inArchiveData: data)
    }

    static func data(forEntryNamed name: String, in archive: URL) throws -> Data {
        guard let entry = try entries(in: archive).first(where: { $0.name == name }) else {
            throw NativeDownloadError.unsupported("ZIP entry was not found: \(name)")
        }
        return try data(for: entry, in: archive)
    }

    static func data(for entry: Entry, inArchiveData data: Data) throws -> Data {
        guard entry.uncompressedSize <= UInt64(Int.max),
              entry.compressedSize <= UInt64(Int.max) else {
            throw NativeDownloadError.unsupported("ZIP entry exceeds supported memory limits.")
        }

        let compressed = try compressedData(for: entry, in: data)
        let output: Data
        switch entry.compressionMethod {
        case 0:
            output = compressed
        case 8:
            output = try inflateRawDeflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw NativeDownloadError.unsupported("ZIP compression method \(entry.compressionMethod) is not supported.")
        }

        guard output.count == Int(entry.uncompressedSize) else {
            throw NativeDownloadError.unsupported("ZIP entry size did not match the central directory.")
        }
        guard ZipCRC32.checksum(output) == entry.crc32 else {
            throw NativeDownloadError.unsupported("ZIP entry checksum did not match the central directory.")
        }
        return output
    }

    private static func compressedData(for entry: Entry, in data: Data) throws -> Data {
        guard entry.localHeaderOffset <= UInt64(Int.max),
              entry.compressedSize <= UInt64(Int.max) else {
            throw NativeDownloadError.unsupported("ZIP entry exceeds supported address limits.")
        }

        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= data.count,
              try uint32(at: offset, in: data) == 0x04034b50 else {
            throw NativeDownloadError.unsupported("ZIP local file header is invalid.")
        }

        let nameLength = Int(try uint16(at: offset + 26, in: data))
        let extraLength = Int(try uint16(at: offset + 28, in: data))
        let dataStart = offset + 30 + nameLength + extraLength
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataStart >= 0,
              dataStart <= data.count,
              dataEnd <= data.count else {
            throw NativeDownloadError.unsupported("ZIP entry data range is invalid.")
        }

        return data.subdata(in: dataStart..<dataEnd)
    }

    private static func inflateRawDeflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0,
              input.count <= Int(UInt32.max),
              expectedSize <= Int(UInt32.max) else {
            throw NativeDownloadError.unsupported("ZIP entry exceeds supported deflate limits.")
        }
        guard expectedSize > 0 else { return Data() }

        var output = Data(count: expectedSize)
        let outputCount = output.count
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw NativeDownloadError.unsupported("ZIP deflate stream could not be initialized.")
        }
        defer { inflateEnd(&stream) }

        let status: Int32 = try input.withUnsafeBytes { inputBuffer in
            try output.withUnsafeMutableBytes { outputBuffer in
                guard let inputBase = inputBuffer.baseAddress,
                      let outputBase = outputBuffer.baseAddress else {
                    throw NativeDownloadError.unsupported("ZIP deflate buffer is invalid.")
                }

                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBase.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outputCount)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard status == Z_STREAM_END,
              stream.avail_in == 0,
              stream.total_out == uLong(expectedSize) else {
            throw NativeDownloadError.unsupported("ZIP deflate entry could not be decompressed.")
        }
        return output
    }

    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minimum = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= minimum {
            if (try? uint32(at: offset, in: data)) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private static func centralDirectoryInfo(eocd: Int, in data: Data) throws -> CentralDirectoryInfo {
        let entryCount16 = try uint16(at: eocd + 10, in: data)
        let centralDirectorySize32 = try uint32(at: eocd + 12, in: data)
        let centralDirectoryOffset32 = try uint32(at: eocd + 16, in: data)
        let needsZIP64 = entryCount16 == UInt16.max ||
            centralDirectorySize32 == UInt32.max ||
            centralDirectoryOffset32 == UInt32.max

        guard needsZIP64 else {
            return CentralDirectoryInfo(
                entryCount: UInt64(entryCount16),
                size: UInt64(centralDirectorySize32),
                offset: UInt64(centralDirectoryOffset32)
            )
        }

        guard let locator = zip64EndOfCentralDirectoryLocatorOffset(before: eocd, in: data) else {
            throw NativeDownloadError.unsupported("ZIP64 end of central directory locator was not found.")
        }

        let zip64EOCDOffset = try uint64(at: locator + 8, in: data)
        guard zip64EOCDOffset <= UInt64(Int.max) else {
            throw NativeDownloadError.unsupported("ZIP64 central directory offset exceeds supported limits.")
        }

        let recordOffset = Int(zip64EOCDOffset)
        guard recordOffset + 56 <= data.count,
              try uint32(at: recordOffset, in: data) == 0x06064b50 else {
            throw NativeDownloadError.unsupported("ZIP64 end of central directory record is invalid.")
        }

        let recordSize = try uint64(at: recordOffset + 4, in: data)
        guard recordSize >= 44,
              recordSize <= UInt64(Int.max),
              recordOffset + 12 + Int(recordSize) <= data.count else {
            throw NativeDownloadError.unsupported("ZIP64 end of central directory record length is invalid.")
        }

        return CentralDirectoryInfo(
            entryCount: try uint64(at: recordOffset + 32, in: data),
            size: try uint64(at: recordOffset + 40, in: data),
            offset: try uint64(at: recordOffset + 48, in: data)
        )
    }

    private static func zip64EndOfCentralDirectoryLocatorOffset(before eocd: Int, in data: Data) -> Int? {
        let locator = eocd - 20
        guard locator >= 0,
              locator + 20 <= data.count,
              (try? uint32(at: locator, in: data)) == 0x07064b50 else {
            return nil
        }
        return locator
    }

    private static func resolvedZIP64EntryFields(
        compressedSize compressedSize32: UInt32,
        uncompressedSize uncompressedSize32: UInt32,
        localHeaderOffset localHeaderOffset32: UInt32,
        extra: Data
    ) throws -> (compressedSize: UInt64, uncompressedSize: UInt64, localHeaderOffset: UInt64) {
        let needsUncompressedSize = uncompressedSize32 == UInt32.max
        let needsCompressedSize = compressedSize32 == UInt32.max
        let needsLocalHeaderOffset = localHeaderOffset32 == UInt32.max
        guard needsUncompressedSize || needsCompressedSize || needsLocalHeaderOffset else {
            return (
                compressedSize: UInt64(compressedSize32),
                uncompressedSize: UInt64(uncompressedSize32),
                localHeaderOffset: UInt64(localHeaderOffset32)
            )
        }

        var offset = 0
        while offset + 4 <= extra.count {
            let headerID = try uint16(at: offset, in: extra)
            let dataSize = Int(try uint16(at: offset + 2, in: extra))
            let valueStart = offset + 4
            let valueEnd = valueStart + dataSize
            guard valueEnd <= extra.count else {
                throw NativeDownloadError.unsupported("ZIP64 extra field length is invalid.")
            }

            if headerID == 0x0001 {
                var cursor = valueStart
                var uncompressedSize = UInt64(uncompressedSize32)
                var compressedSize = UInt64(compressedSize32)
                var localHeaderOffset = UInt64(localHeaderOffset32)

                if needsUncompressedSize {
                    guard cursor + 8 <= valueEnd else {
                        throw NativeDownloadError.unsupported("ZIP64 uncompressed size is missing.")
                    }
                    uncompressedSize = try uint64(at: cursor, in: extra)
                    cursor += 8
                }
                if needsCompressedSize {
                    guard cursor + 8 <= valueEnd else {
                        throw NativeDownloadError.unsupported("ZIP64 compressed size is missing.")
                    }
                    compressedSize = try uint64(at: cursor, in: extra)
                    cursor += 8
                }
                if needsLocalHeaderOffset {
                    guard cursor + 8 <= valueEnd else {
                        throw NativeDownloadError.unsupported("ZIP64 local header offset is missing.")
                    }
                    localHeaderOffset = try uint64(at: cursor, in: extra)
                }

                return (
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }

            offset = valueEnd
        }

        throw NativeDownloadError.unsupported("ZIP64 entry extra field was not found.")
    }

    private static func decodedEntryName(from data: Data, generalPurposeBitFlag: UInt16) -> String? {
        let encodings: [String.Encoding]
        if (generalPurposeBitFlag & 0x0800) != 0 {
            encodings = [.utf8]
        } else {
            encodings = [
                .utf8,
                Self.dosKoreanEncoding,
                Self.dosJapaneseEncoding,
                Self.dosLatinUSEncoding,
                .windowsCP1252,
                .isoLatin1
            ]
        }

        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding)?.replacingOccurrences(of: "\\", with: "/"),
               !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    private static func isSafeEntryName(_ name: String) -> Bool {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.hasPrefix("../"),
              !normalized.contains("/../"),
              !normalized.contains("\0") else {
            return false
        }
        if normalized.hasPrefix("__MACOSX/") || normalized.hasSuffix("/.DS_Store") || normalized == ".DS_Store" {
            return false
        }
        return true
    }

    private static let dosLatinUSEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue))
    )

    private static let dosKoreanEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
    )

    private static let dosJapaneseEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
    )


    private static func uint16(at offset: Int, in data: Data) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw NativeDownloadError.unsupported("ZIP integer is out of range.")
        }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(at offset: Int, in data: Data) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw NativeDownloadError.unsupported("ZIP integer is out of range.")
        }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func uint64(at offset: Int, in data: Data) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else {
            throw NativeDownloadError.unsupported("ZIP integer is out of range.")
        }
        return UInt64(data[offset]) |
            (UInt64(data[offset + 1]) << 8) |
            (UInt64(data[offset + 2]) << 16) |
            (UInt64(data[offset + 3]) << 24) |
            (UInt64(data[offset + 4]) << 32) |
            (UInt64(data[offset + 5]) << 40) |
            (UInt64(data[offset + 6]) << 48) |
            (UInt64(data[offset + 7]) << 56)
    }
}

private enum ZipCRC32 {
    static let initial: UInt32 = 0xffffffff

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        finalize(update(initial, data: data))
    }

    private static func update(_ crc: UInt32, data: Data) -> UInt32 {
        var result = crc
        data.withUnsafeBytes { buffer in
            for byte in buffer.bindMemory(to: UInt8.self) {
                result = table[Int((result ^ UInt32(byte)) & 0xff)] ^ (result >> 8)
            }
        }
        return result
    }

    private static func finalize(_ crc: UInt32) -> UInt32 {
        crc ^ 0xffffffff
    }
}
