import AppKit
import Foundation
import UniformTypeIdentifiers

struct QueueJobDropTarget: Equatable {
    let jobID: UUID
    let placeAfter: Bool
}

enum QueueDropTypes {
    static let queueJob = UTType(
        exportedAs: "io.github.nowonwantsthis.hitomibadayo.queue-job",
        conformingTo: .data
    )

    static let externalTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.utf8PlainText.identifier,
        UTType.plainText.identifier
    ]

    static let internalTypeIdentifiers = [
        queueJob.identifier,
        UTType.data.identifier
    ]

    static func jobProvider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: queueJob.identifier,
            visibility: .all
        ) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    static func jobPasteboardItem(for id: UUID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let data = Data(id.uuidString.utf8)
        item.setData(data, forType: NSPasteboard.PasteboardType(queueJob.identifier))
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.data.identifier))
        return item
    }
}

enum QueueDropInputLoader {
    static func load(_ providers: [NSItemProvider]) async -> [String] {
        var values: [String] = []
        for provider in providers {
            if let url = await loadURL(from: provider) {
                values.append(url.isFileURL ? url.standardizedFileURL.absoluteString : url.absoluteString)
                continue
            }
            if let text = await loadText(from: provider), !text.trimmed.isEmpty {
                values.append(text)
            }
        }
        return values
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: NSURL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL {
                    continuation.resume(returning: url)
                } else if let url = object as? NSURL {
                    continuation.resume(returning: url as URL)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        let identifiers = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            UTType.url.identifier
        ]
        for identifier in identifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let data = await loadData(from: provider, typeIdentifier: identifier),
               let text = decodedText(from: data),
               !text.trimmed.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func decodedText(from data: Data) -> String? {
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian
        ] {
            if let value = String(data: data, encoding: encoding) {
                return value.trimmingCharacters(in: .controlCharacters)
            }
        }
        return nil
    }
}
