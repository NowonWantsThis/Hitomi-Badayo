import Foundation

enum ZipArchiveWriter {
    private struct CentralDirectoryEntry {
        var name: Data
        var crc32: UInt32
        var size: UInt32
        var localHeaderOffset: UInt32
    }

    static func archiveDirectory(_ directory: URL, to destination: URL, fileManager: FileManager = .default) throws {
        let files = try archiveFileURLs(in: directory, fileManager: fileManager)
        try? fileManager.removeItem(at: destination)
        fileManager.createFile(atPath: destination.path, contents: nil)

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var entries: [CentralDirectoryEntry] = []
        for file in files {
            let relativePath = try archiveRelativePath(for: file, baseDirectory: directory)
            let nameData = Data(relativePath.utf8)
            let info = try fileInfo(for: file)
            let offset = try uint32(output.offsetInFile, label: "ZIP offset")

            try writeLocalHeader(name: nameData, info: info, to: output)
            try copyFile(file, to: output)
            entries.append(CentralDirectoryEntry(
                name: nameData,
                crc32: info.crc32,
                size: info.size,
                localHeaderOffset: offset
            ))
        }

        let centralOffset = try uint32(output.offsetInFile, label: "ZIP central offset")
        for entry in entries {
            try writeCentralDirectory(entry: entry, to: output)
        }
        let centralSize = try uint32(output.offsetInFile - UInt64(centralOffset), label: "ZIP central size")
        try writeEndOfCentralDirectory(entryCount: entries.count, centralSize: centralSize, centralOffset: centralOffset, to: output)
    }

    private static func archiveFileURLs(in directory: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func archiveRelativePath(for file: URL, baseDirectory: URL) throws -> String {
        let base = baseDirectory.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : "\(base)/"
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(prefix) else {
            throw NativeDownloadError.unsupported("File is outside the archive directory.")
        }
        return String(path.dropFirst(prefix.count)).replacingOccurrences(of: "\\", with: "/")
    }

    private static func fileInfo(for file: URL) throws -> (crc32: UInt32, size: UInt32) {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }

        var crc = CRC32.initial
        var size: UInt64 = 0
        while true {
            let chunk = input.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            crc = CRC32.update(crc, data: chunk)
            size += UInt64(chunk.count)
        }
        return (CRC32.finalize(crc), try uint32(size, label: "ZIP file size"))
    }

    private static func copyFile(_ file: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }

        while true {
            let chunk = input.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            output.write(chunk)
        }
    }

    private static func writeLocalHeader(name: Data, info: (crc32: UInt32, size: UInt32), to output: FileHandle) throws {
        try writeUInt32(0x04034b50, to: output)
        try writeUInt16(20, to: output)
        try writeUInt16(0x0800, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0x0021, to: output)
        try writeUInt32(info.crc32, to: output)
        try writeUInt32(info.size, to: output)
        try writeUInt32(info.size, to: output)
        try writeUInt16(uint16(name.count, label: "ZIP file name length"), to: output)
        try writeUInt16(0, to: output)
        output.write(name)
    }

    private static func writeCentralDirectory(entry: CentralDirectoryEntry, to output: FileHandle) throws {
        try writeUInt32(0x02014b50, to: output)
        try writeUInt16(20, to: output)
        try writeUInt16(20, to: output)
        try writeUInt16(0x0800, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0x0021, to: output)
        try writeUInt32(entry.crc32, to: output)
        try writeUInt32(entry.size, to: output)
        try writeUInt32(entry.size, to: output)
        try writeUInt16(uint16(entry.name.count, label: "ZIP file name length"), to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt32(0, to: output)
        try writeUInt32(entry.localHeaderOffset, to: output)
        output.write(entry.name)
    }

    private static func writeEndOfCentralDirectory(entryCount: Int, centralSize: UInt32, centralOffset: UInt32, to output: FileHandle) throws {
        let count = try uint16(entryCount, label: "ZIP entry count")
        try writeUInt32(0x06054b50, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(0, to: output)
        try writeUInt16(count, to: output)
        try writeUInt16(count, to: output)
        try writeUInt32(centralSize, to: output)
        try writeUInt32(centralOffset, to: output)
        try writeUInt16(0, to: output)
    }

    private static func writeUInt16(_ value: UInt16, to output: FileHandle) throws {
        var littleEndian = value.littleEndian
        output.write(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    private static func writeUInt32(_ value: UInt32, to output: FileHandle) throws {
        var littleEndian = value.littleEndian
        output.write(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    private static func uint16(_ value: Int, label: String) throws -> UInt16 {
        guard value <= Int(UInt16.max) else {
            throw NativeDownloadError.unsupported("\(label) exceeds ZIP limits.")
        }
        return UInt16(value)
    }

    private static func uint32(_ value: UInt64, label: String) throws -> UInt32 {
        guard value <= UInt64(UInt32.max) else {
            throw NativeDownloadError.unsupported("\(label) exceeds ZIP32 limits.")
        }
        return UInt32(value)
    }
}

private enum CRC32 {
    static let initial: UInt32 = 0xffffffff

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func update(_ crc: UInt32, data: Data) -> UInt32 {
        var result = crc
        data.withUnsafeBytes { buffer in
            for byte in buffer.bindMemory(to: UInt8.self) {
                result = table[Int((result ^ UInt32(byte)) & 0xff)] ^ (result >> 8)
            }
        }
        return result
    }

    static func finalize(_ crc: UInt32) -> UInt32 {
        crc ^ 0xffffffff
    }
}
