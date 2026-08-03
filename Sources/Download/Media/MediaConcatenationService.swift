import Foundation

final class MediaConcatenationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func concatenateContents(
        of directory: URL,
        to output: URL
    ) throws {
        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }

        fileManager.createFile(atPath: output.path, contents: nil)
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        try appendFiles(files, to: writer)
    }

    func appendFiles(
        _ files: [URL],
        to writer: FileHandle
    ) throws {
        for file in files.sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            try Task.checkCancellation()
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            while true {
                let chunk = try reader.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty { break }
                try writer.write(contentsOf: chunk)
            }
        }
    }
}
