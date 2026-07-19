import Foundation

enum PixivUgoiraPackageWriter {
    static func package(originalZip: Data, package: PixivUgoiraPackage) throws -> Data {
        guard let eocd = endOfCentralDirectory(in: originalZip),
              eocd.diskNumber == 0,
              eocd.centralDirectoryDisk == 0,
              eocd.entryCount == eocd.entryCountOnDisk,
              eocd.centralDirectoryOffset + eocd.centralDirectorySize <= originalZip.count else {
            throw NativeDownloadError.unsupported("Pixiv ugoira zip metadata could not be rewritten.")
        }

        let animation = try animationJSON(for: package)
        let entryName = Data("animation.json".utf8)
        let crc = CRC32.checksum(animation)
        let newLocalOffset = UInt32(eocd.centralDirectoryOffset)

        var output = Data()
        output.append(originalZip[0..<eocd.centralDirectoryOffset])
        output.append(localFileHeader(name: entryName, data: animation, crc32: crc))
        output.append(animation)

        let newCentralOffset = output.count
        output.append(originalZip[eocd.centralDirectoryOffset..<(eocd.centralDirectoryOffset + eocd.centralDirectorySize)])
        output.append(centralDirectoryHeader(name: entryName, data: animation, crc32: crc, localOffset: newLocalOffset))

        let newCentralSize = output.count - newCentralOffset
        output.append(endOfCentralDirectory(entryCount: eocd.entryCount + 1, centralDirectorySize: UInt32(newCentralSize), centralDirectoryOffset: UInt32(newCentralOffset)))
        return output
    }

    private static func animationJSON(for package: PixivUgoiraPackage) throws -> Data {
        let frames = package.frames.map { ["file": $0.file, "delay": $0.delay] as [String: Any] }
        let object: [String: Any] = [
            "frames": frames,
            "source": package.artworkURL,
            "format": "ugoira"
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func localFileHeader(name: Data, data: Data, crc32: UInt32) -> Data {
        var output = Data()
        output.appendUInt32LE(0x04034b50)
        output.appendUInt16LE(20)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt32LE(crc32)
        output.appendUInt32LE(UInt32(data.count))
        output.appendUInt32LE(UInt32(data.count))
        output.appendUInt16LE(UInt16(name.count))
        output.appendUInt16LE(0)
        output.append(name)
        return output
    }

    private static func centralDirectoryHeader(name: Data, data: Data, crc32: UInt32, localOffset: UInt32) -> Data {
        var output = Data()
        output.appendUInt32LE(0x02014b50)
        output.appendUInt16LE(20)
        output.appendUInt16LE(20)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt32LE(crc32)
        output.appendUInt32LE(UInt32(data.count))
        output.appendUInt32LE(UInt32(data.count))
        output.appendUInt16LE(UInt16(name.count))
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt32LE(0)
        output.appendUInt32LE(localOffset)
        output.append(name)
        return output
    }

    private static func endOfCentralDirectory(entryCount: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) -> Data {
        var output = Data()
        output.appendUInt32LE(0x06054b50)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(entryCount)
        output.appendUInt16LE(entryCount)
        output.appendUInt32LE(centralDirectorySize)
        output.appendUInt32LE(centralDirectoryOffset)
        output.appendUInt16LE(0)
        return output
    }

    private static func endOfCentralDirectory(in data: Data) -> EndOfCentralDirectory? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        var index = data.count - 22
        while index >= lowerBound {
            if data.uint32LE(at: index) == 0x06054b50 {
                let commentLength = Int(data.uint16LE(at: index + 20))
                guard index + 22 + commentLength == data.count else {
                    index -= 1
                    continue
                }
                let centralSize = Int(data.uint32LE(at: index + 12))
                let centralOffset = Int(data.uint32LE(at: index + 16))
                return EndOfCentralDirectory(
                    diskNumber: data.uint16LE(at: index + 4),
                    centralDirectoryDisk: data.uint16LE(at: index + 6),
                    entryCountOnDisk: data.uint16LE(at: index + 8),
                    entryCount: data.uint16LE(at: index + 10),
                    centralDirectorySize: centralSize,
                    centralDirectoryOffset: centralOffset
                )
            }
            index -= 1
        }
        return nil
    }

    private struct EndOfCentralDirectory {
        var diskNumber: UInt16
        var centralDirectoryDisk: UInt16
        var entryCountOnDisk: UInt16
        var entryCount: UInt16
        var centralDirectorySize: Int
        var centralDirectoryOffset: Int
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xff
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xedb8_8320 : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xffff_ffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) |
            (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[startIndex + offset]) |
            (UInt32(self[startIndex + offset + 1]) << 8) |
            (UInt32(self[startIndex + offset + 2]) << 16) |
            (UInt32(self[startIndex + offset + 3]) << 24)
    }
}
