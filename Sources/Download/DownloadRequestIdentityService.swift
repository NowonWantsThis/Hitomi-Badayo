import Foundation

enum DownloadRequestIdentityService {
    static func isAudioExtractionRequest(
        _ metadata: [String: String]
    ) -> Bool {
        metadata["media_request"]?.lowercased() == "audio"
    }

    static func ytdlpAudioFormat(
        from metadata: [String: String]
    ) -> String? {
        guard isAudioExtractionRequest(metadata) else { return nil }
        let format = metadata["audio_format"]?.trimmed.lowercased() ?? "mp3"
        return format.isEmpty ? "mp3" : format
    }

    static func duplicateKey(
        source: String,
        normalizedSource: String? = nil,
        metadata: [String: String] = [:]
    ) -> String {
        let normalized = normalizedSource ?? URLIdentity.normalize(source)
        let request = isAudioExtractionRequest(metadata)
            ? "audio:\(ytdlpAudioFormat(from: metadata) ?? "mp3")"
            : "default"
        let originalType = metadata[OriginalInputType.metadataKey]?.lowercased()
            ?? ""
        return normalized + "\u{1f}" + request + "\u{1f}" + originalType
    }
}
