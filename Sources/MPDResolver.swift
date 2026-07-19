import Foundation

final class MPDResolver {
    func canResolve(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return url.path.lowercased().hasSuffix(".mpd") || lower.contains(".mpd")
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let xml = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        let manifest = try MPDParser.parse(xml)

        if let video = manifest.bestVideoRepresentation(),
           let audio = manifest.bestAudioRepresentation() {
            let videoAssets = try await video.assets(baseURL: url, headers: headers)
            let audioAssets = try await audio.assets(baseURL: url, headers: headers)
            guard !videoAssets.isEmpty && !audioAssets.isEmpty else {
                throw NativeDownloadError.noFiles
            }

            let title = title(from: url).sanitizedFilename()
            return ResolvedDownload(
                title: title,
                folderName: "\(title) dash".sanitizedFilename(),
                assets: videoAssets + audioAssets,
                packageMode: .mux(
                    videoAssets: videoAssets,
                    audioAssets: audioAssets,
                    outputFilename: "\(title).mp4".sanitizedFilename()
                ),
                metadata: Self.dashMetadata(
                    title: title,
                    manifestURL: url,
                    mode: "mux",
                    video: video,
                    audio: audio,
                    representation: nil,
                    assets: videoAssets + audioAssets,
                    duration: manifest.mediaPresentationDuration
                )
            )
        }

        guard let representation = manifest.bestRepresentation() else {
            throw NativeDownloadError.unsupported("No playable DASH representation was found.")
        }

        let assets = try await representation.assets(baseURL: url, headers: headers)
        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = title(from: url).sanitizedFilename()
        let outputExtension = representation.outputExtension
        return ResolvedDownload(
            title: title,
            folderName: "\(title) dash".sanitizedFilename(),
            assets: assets,
            packageMode: .concatenate(outputFilename: "\(title).\(outputExtension)".sanitizedFilename()),
            metadata: Self.dashMetadata(
                title: title,
                manifestURL: url,
                mode: "concatenate",
                video: representation.isVideo ? representation : nil,
                audio: representation.isAudio ? representation : nil,
                representation: representation,
                assets: assets,
                duration: manifest.mediaPresentationDuration
            )
        )
    }

    private static func dashMetadata(
        title: String,
        manifestURL: URL,
        mode: String,
        video: MPDRepresentation?,
        audio: MPDRepresentation?,
        representation: MPDRepresentation?,
        assets: [ResolvedAsset],
        duration: Double?
    ) -> [String: String] {
        let selected = representation ?? video ?? audio
        return DownloadMetadata.clean([
            "series": title,
            "category": "video",
            "type": "dash",
            "format": "mpd",
            "package_mode": mode,
            "host": manifestURL.host ?? "",
            "site": manifestURL.host ?? "MPD",
            "manifest_url": manifestURL.absoluteString,
            "media_url": manifestURL.absoluteString,
            "source_url": manifestURL.absoluteString,
            "page_url": manifestURL.absoluteString,
            "representation_id": selected?.id ?? "",
            "video_representation_id": video?.id ?? "",
            "audio_representation_id": audio?.id ?? "",
            "bandwidth": selected.map { String($0.bandwidth) } ?? "",
            "video_bandwidth": video.map { String($0.bandwidth) } ?? "",
            "audio_bandwidth": audio.map { String($0.bandwidth) } ?? "",
            "mime_type": selected?.mimeType ?? "",
            "media_count": String(assets.count),
            "video_count": video == nil && audio != nil ? "" : "1",
            "audio_count": audio == nil ? "" : "1",
            "segment_count": String(assets.count),
            "duration_seconds": duration.map { String(format: "%.3f", $0) } ?? "",
            "slug": title,
            "title": title
        ])
    }

    private func title(from url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        return last.isEmpty ? "manifest" : last
    }
}

private struct MPDManifest {
    var mediaPresentationDuration: Double?
    var representations: [MPDRepresentation]

    func bestRepresentation() -> MPDRepresentation? {
        representations.filter { !$0.isProtected }.max { lhs, rhs in
            if lhs.isVideo != rhs.isVideo {
                return !lhs.isVideo && rhs.isVideo
            }
            return lhs.bandwidth < rhs.bandwidth
        }
    }

    func bestVideoRepresentation() -> MPDRepresentation? {
        representations
            .filter { $0.isVideo && !$0.isProtected }
            .max { $0.bandwidth < $1.bandwidth }
    }

    func bestAudioRepresentation() -> MPDRepresentation? {
        representations
            .filter { $0.isAudio && !$0.isProtected }
            .max { $0.bandwidth < $1.bandwidth }
    }
}

private struct MPDRepresentation {
    var id: String
    var bandwidth: Int
    var mimeType: String
    var basePath: String
    var mediaPresentationDuration: Double?
    var template: SegmentTemplate?
    var list: SegmentList?
    var segmentBase: SegmentBase?
    var isProtected: Bool

    var isVideo: Bool {
        let lower = mimeType.lowercased()
        return lower == "video" || lower.contains("video")
    }

    var isAudio: Bool {
        let lower = mimeType.lowercased()
        return lower == "audio" || lower.contains("audio")
    }

    var outputExtension: String {
        if template == nil,
           list == nil,
           let extensionFromBaseURL = Self.pathExtension(from: basePath) {
            return extensionFromBaseURL
        }
        if mimeType.lowercased().contains("mp4") {
            return "mp4"
        }
        if mimeType.lowercased().contains("webm") {
            return "webm"
        }
        return "m4s"
    }

    func assets(baseURL: URL, headers: HTTPRequestOptions) async throws -> [ResolvedAsset] {
        if let template {
            return try assetsFromTemplate(template, baseURL: baseURL, headers: headers)
        }
        if let list {
            return try assetsFromList(list, baseURL: baseURL, headers: headers)
        }
        if let segmentBase {
            return try await assetsFromSegmentBase(segmentBase, baseURL: baseURL, headers: headers)
        }
        return try assetsFromBaseURL(baseURL: baseURL, headers: headers)
    }

    private func assetsFromTemplate(
        _ template: SegmentTemplate,
        baseURL: URL,
        headers: HTTPRequestOptions
    ) throws -> [ResolvedAsset] {
        guard let mediaTemplate = template.media.dashNonEmpty else {
            throw NativeDownloadError.unsupported("DASH SegmentTemplate has no media pattern.")
        }
        var assets: [ResolvedAsset] = []
        var index = 0
        let startNumber = template.startNumber ?? 1

        if let initialization = template.initialization.dashNonEmpty {
            let path = expand(template: initialization, number: startNumber, time: nil)
            let remote = try resolve(path: path, basePath: basePath, baseURL: baseURL)
            assets.append(asset(
                remoteURL: remote,
                filename: String(format: "%06d-init.%@", index, remote.pathExtensionOr("mp4")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_initialization",
                byteRange: nil,
                headers: headers
            ))
            index += 1
        }

        let segmentRefs = try template.segmentRefs(totalDuration: mediaPresentationDuration)
        for ref in segmentRefs {
            let path = expand(template: mediaTemplate, number: ref.number, time: ref.time)
            let remote = try resolve(path: path, basePath: basePath, baseURL: baseURL)
            assets.append(asset(
                remoteURL: remote,
                filename: String(format: "%06d.%@", index, remote.pathExtensionOr("m4s")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_segment",
                byteRange: nil,
                headers: headers
            ))
            index += 1
        }

        return assets
    }

    private func assetsFromBaseURL(baseURL: URL, headers: HTTPRequestOptions) throws -> [ResolvedAsset] {
        guard !basePath.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("DASH representation has no supported segment description.")
        }
        let remote = try resolve(path: basePath, basePath: "", baseURL: baseURL)
        return [
            asset(
                remoteURL: remote,
                filename: String(format: "%06d.%@", 0, remote.pathExtensionOr(outputExtension)),
                manifestURL: baseURL,
                index: 0,
                kind: "dash_media",
                byteRange: nil,
                headers: headers
            )
        ]
    }

    private func assetsFromList(
        _ list: SegmentList,
        baseURL: URL,
        headers: HTTPRequestOptions
    ) throws -> [ResolvedAsset] {
        var assets: [ResolvedAsset] = []
        var index = 0

        if let initialization = list.initialization {
            let remote = try resolve(resource: initialization, baseURL: baseURL)
            assets.append(asset(
                remoteURL: remote,
                filename: String(format: "%06d-init.%@", index, remote.pathExtensionOr("mp4")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_initialization",
                byteRange: initialization.byteRange,
                headers: headers
            ))
            index += 1
        }

        for media in list.segments {
            let remote = try resolve(resource: media, baseURL: baseURL)
            assets.append(asset(
                remoteURL: remote,
                filename: String(format: "%06d.%@", index, remote.pathExtensionOr("m4s")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_segment",
                byteRange: media.byteRange,
                headers: headers
            ))
            index += 1
        }

        return assets
    }

    private func assetsFromSegmentBase(
        _ segmentBase: SegmentBase,
        baseURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> [ResolvedAsset] {
        guard !basePath.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("DASH SegmentBase has no media BaseURL.")
        }

        let mediaURL = try resolve(path: basePath, basePath: "", baseURL: baseURL)
        let indexResource = segmentBase.indexResource ?? DASHSegmentResource(path: nil, byteRange: segmentBase.indexRange)
        guard let indexRange = indexResource.byteRange else {
            return try assetsFromBaseURL(baseURL: baseURL, headers: headers)
        }

        let indexURL = try resolve(resource: indexResource, baseURL: baseURL)
        guard indexURL == mediaURL else {
            throw NativeDownloadError.unsupported("DASH SegmentBase with a separate RepresentationIndex URL is not supported.")
        }

        let rangeHeader = indexRange.headerValue
        let (indexData, response) = try await HTTPClient.shared.dataResponse(
            from: indexURL,
            referer: headers.referer ?? baseURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: [
                "Range": rangeHeader,
                "Accept-Encoding": "identity"
            ]
        )
        let absoluteDataOffset: Int64
        if response.statusCode == 206 {
            absoluteDataOffset = Self.contentRangeStart(response.value(forHTTPHeaderField: "Content-Range")) ?? indexRange.start
        } else {
            absoluteDataOffset = 0
        }

        let sidx = try DASHSIDXParser.parse(data: indexData, absoluteDataOffset: absoluteDataOffset)
        var assets: [ResolvedAsset] = []
        var index = 0

        let initialization: DASHSegmentResource?
        if let explicit = segmentBase.initialization {
            initialization = explicit
        } else if indexURL == mediaURL, indexRange.start > 0 {
            initialization = DASHSegmentResource(
                path: nil,
                byteRange: DASHByteRange(start: 0, end: indexRange.start - 1)
            )
        } else {
            initialization = nil
        }

        if let initialization {
            let remote = try resolve(resource: initialization, baseURL: baseURL)
            assets.append(asset(
                remoteURL: remote,
                filename: String(format: "%06d-init.%@", index, remote.pathExtensionOr("mp4")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_initialization",
                byteRange: initialization.byteRange,
                headers: headers,
                extraMetadata: [
                    "sidx_timescale": String(sidx.timescale),
                    "sidx_reference_count": String(sidx.references.count)
                ]
            ))
            index += 1
        }

        for reference in sidx.references {
            assets.append(asset(
                remoteURL: mediaURL,
                filename: String(format: "%06d.%@", index, mediaURL.pathExtensionOr("m4s")),
                manifestURL: baseURL,
                index: index,
                kind: "dash_segment",
                byteRange: reference.byteRange,
                headers: headers,
                extraMetadata: [
                    "segment_duration": String(reference.duration),
                    "sidx_timescale": String(sidx.timescale),
                    "sidx_reference_count": String(sidx.references.count)
                ]
            ))
            index += 1
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return assets
    }

    private func asset(
        remoteURL: URL,
        filename: String,
        manifestURL: URL,
        index: Int,
        kind: String,
        byteRange: DASHByteRange?,
        headers: HTTPRequestOptions,
        extraMetadata: [String: String] = [:]
    ) -> ResolvedAsset {
        var metadata = assetMetadata(
            for: remoteURL,
            manifestURL: manifestURL,
            index: index,
            kind: kind,
            byteRange: byteRange
        )
        metadata.merge(extraMetadata) { _, newValue in newValue }
        return ResolvedAsset(
            remoteURL: remoteURL,
            filename: filename,
            metadata: metadata,
            referer: headers.referer ?? manifestURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: byteRange.map {
                [
                    ResolvedRequestHeader(name: "Range", value: $0.headerValue),
                    ResolvedRequestHeader(name: "Accept-Encoding", value: "identity")
                ]
            } ?? []
        )
    }

    private func expand(template: String, number: Int, time: Int64?) -> String {
        let escapedDollar = "\u{0}DASH_DOLLAR\u{0}"
        var result = template.replacingOccurrences(of: "$$", with: escapedDollar)
        result = result.replacingOccurrences(of: "$RepresentationID$", with: id)
        result = replaceNumberTokens(in: result, number: number)
        if let time {
            result = replaceInt64Tokens(in: result, name: "Time", value: time)
        }
        result = replaceInt64Tokens(in: result, name: "Bandwidth", value: Int64(bandwidth))
        result = result.replacingOccurrences(of: escapedDollar, with: "$")
        return result
    }

    private func replaceNumberTokens(in input: String, number: Int) -> String {
        let pattern = #"\$Number(?:%0([0-9]+)d)?\$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input.replacingOccurrences(of: "$Number$", with: String(number))
        }

        var result = input
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: result) else { continue }
            var replacement = String(number)
            if match.numberOfRanges > 1,
               let widthRange = Range(match.range(at: 1), in: input),
               let width = Int(input[widthRange]) {
                replacement = String(format: "%0\(width)d", number)
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private func replaceInt64Tokens(in input: String, name: String, value: Int64) -> String {
        let pattern = #"\$"# + NSRegularExpression.escapedPattern(for: name) + #"(?:%0([0-9]+)d)?\$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input.replacingOccurrences(of: "$\(name)$", with: String(value))
        }

        var result = input
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: result) else { continue }
            var replacement = String(value)
            if match.numberOfRanges > 1,
               let widthRange = Range(match.range(at: 1), in: input),
               let width = Int(input[widthRange]),
               width > 0,
               width <= 64 {
                replacement = String(format: "%0\(width)lld", value)
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private func resolve(resource: DASHSegmentResource, baseURL: URL) throws -> URL {
        try resolve(path: resource.path ?? "", basePath: basePath, baseURL: baseURL)
    }

    private func resolve(path: String, basePath: String, baseURL: URL) throws -> URL {
        let cleanedPath = path.trimmed
        let combined: URL?
        if cleanedPath.hasPrefix("//") {
            combined = URL(string: (baseURL.scheme ?? "https") + ":" + cleanedPath)
        } else if cleanedPath.hasPrefix("http://") || cleanedPath.hasPrefix("https://") {
            combined = URL(string: cleanedPath)
        } else if !basePath.trimmed.isEmpty {
            guard let resolvedBase = URL(string: basePath, relativeTo: baseURL)?.absoluteURL else {
                throw NativeDownloadError.invalidPlaylist
            }
            combined = cleanedPath.isEmpty ? resolvedBase : URL(string: cleanedPath, relativeTo: resolvedBase)?.absoluteURL
        } else {
            combined = URL(string: cleanedPath, relativeTo: baseURL)?.absoluteURL
        }

        guard let url = combined?.absoluteURL else {
            throw NativeDownloadError.invalidPlaylist
        }
        return url
    }

    private func assetMetadata(
        for url: URL,
        manifestURL: URL,
        index: Int,
        kind: String,
        byteRange: DASHByteRange?
    ) -> [String: String] {
        let trackType = isVideo ? "video" : (isAudio ? "audio" : "media")
        let format = url.pathExtension.trimmed.isEmpty ? outputExtension : url.pathExtension.lowercased()
        return DownloadMetadata.clean([
            "type": kind,
            "media_type": kind,
            "track_type": trackType,
            "page": String(index + 1),
            "position": String(index + 1),
            "segment_index": String(index),
            "representation_id": id,
            "bandwidth": String(bandwidth),
            "mime_type": mimeType,
            "format": format,
            "media_format": format,
            "manifest_url": manifestURL.absoluteString,
            "media_url": url.absoluteString,
            "video_url": isVideo ? url.absoluteString : "",
            "audio_url": isAudio ? url.absoluteString : "",
            "source_url": url.absoluteString,
            "page_url": manifestURL.absoluteString,
            "byte_range": byteRange?.headerValue ?? "",
            "range_start": byteRange.map { String($0.start) } ?? "",
            "range_end": byteRange.map { String($0.end) } ?? ""
        ])
    }

    private static func contentRangeStart(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let pattern = #"(?i)^bytes\s+(\d+)-\d+/(?:\d+|\*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Int64(value[range])
    }

    private static func pathExtension(from value: String) -> String? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              !url.pathExtension.isEmpty else {
            return nil
        }
        return url.pathExtension.lowercased()
    }
}

private struct SegmentTemplate {
    static let maximumSegmentCount = 100_000

    var initialization: String?
    var media: String?
    var startNumber: Int?
    var timescale: Int?
    var duration: Int64?
    var presentationTimeOffset: Int64?
    var timeline: [TimelineSegment] = []

    func segmentRefs(totalDuration: Double?) throws -> [SegmentRef] {
        let firstNumber = startNumber ?? 1
        let scale = timescale ?? 1
        guard firstNumber >= 0, scale > 0 else {
            throw NativeDownloadError.unsupported("DASH SegmentTemplate has an invalid start number or timescale.")
        }

        if !timeline.isEmpty {
            var refs: [SegmentRef] = []
            var number = firstNumber
            var currentTime: Int64 = 0

            for (segmentIndex, segment) in timeline.enumerated() {
                if let start = segment.start {
                    guard start >= 0 else {
                        throw NativeDownloadError.unsupported("DASH SegmentTimeline contains a negative start time.")
                    }
                    currentTime = start
                }
                guard segment.duration > 0 else { continue }

                let occurrenceCount: Int
                if segment.repeatCount >= 0 {
                    guard segment.repeatCount < Self.maximumSegmentCount else {
                        throw NativeDownloadError.unsupported("DASH manifest exceeds the segment safety limit.")
                    }
                    occurrenceCount = segment.repeatCount + 1
                } else if timeline.indices.contains(segmentIndex + 1),
                          let nextStart = timeline[segmentIndex + 1].start {
                    guard let count = Self.occurrenceCount(
                        from: currentTime,
                        to: nextStart,
                        duration: segment.duration
                    ) else {
                        throw NativeDownloadError.unsupported("DASH SegmentTimeline repeat range overflowed.")
                    }
                    occurrenceCount = count
                } else if let totalDuration,
                          totalDuration.isFinite,
                          totalDuration > 0 {
                    let rawPeriodUnits = ceil(totalDuration * Double(scale))
                    guard rawPeriodUnits <= Double(Int64.max),
                          (presentationTimeOffset ?? 0) >= 0 else {
                        throw NativeDownloadError.unsupported("DASH Period duration overflowed the media timeline.")
                    }
                    let periodUnits = Int64(rawPeriodUnits)
                    let (periodEnd, periodOverflowed) = (presentationTimeOffset ?? 0).addingReportingOverflow(periodUnits)
                    guard !periodOverflowed,
                          let count = Self.occurrenceCount(
                        from: currentTime,
                        to: periodEnd,
                        duration: segment.duration
                    ) else {
                        throw NativeDownloadError.unsupported("DASH SegmentTimeline repeat range overflowed.")
                    }
                    occurrenceCount = count
                } else {
                    throw NativeDownloadError.unsupported(
                        "DASH SegmentTimeline has an unbounded negative repeat without a Period duration."
                    )
                }

                guard occurrenceCount >= 0,
                      refs.count <= Self.maximumSegmentCount - occurrenceCount else {
                    throw NativeDownloadError.unsupported("DASH manifest exceeds the segment safety limit.")
                }
                for _ in 0..<occurrenceCount {
                    refs.append(SegmentRef(number: number, time: currentTime))
                    let (nextTime, overflowed) = currentTime.addingReportingOverflow(segment.duration)
                    guard !overflowed else {
                        throw NativeDownloadError.unsupported("DASH SegmentTimeline time overflowed.")
                    }
                    currentTime = nextTime
                    let (nextNumber, numberOverflowed) = number.addingReportingOverflow(1)
                    guard !numberOverflowed else {
                        throw NativeDownloadError.unsupported("DASH segment number overflowed.")
                    }
                    number = nextNumber
                }
            }
            return refs
        }

        guard let duration, duration > 0 else { return [] }
        let count: Int
        if let totalDuration, totalDuration.isFinite, totalDuration > 0 {
            let rawCount = ceil(totalDuration / (Double(duration) / Double(scale)))
            guard rawCount <= Double(Self.maximumSegmentCount) else {
                throw NativeDownloadError.unsupported("DASH manifest exceeds the segment safety limit.")
            }
            count = max(1, Int(rawCount))
        } else {
            count = 1
        }
        guard count <= Self.maximumSegmentCount else {
            throw NativeDownloadError.unsupported("DASH manifest exceeds the segment safety limit.")
        }
        guard count == 0 || firstNumber <= Int.max - (count - 1) else {
            throw NativeDownloadError.unsupported("DASH segment number overflowed.")
        }
        return (0..<count).map { SegmentRef(number: firstNumber + $0, time: nil) }
    }

    private static func occurrenceCount(from start: Int64, to end: Int64, duration: Int64) -> Int? {
        guard start >= 0, end > start, duration > 0 else { return 0 }
        let (distance, overflowed) = end.subtractingReportingOverflow(start)
        guard !overflowed else { return nil }
        let quotient = distance / duration
        let remainder = distance % duration
        let rounded = quotient + (remainder == 0 ? 0 : 1)
        return Int(exactly: rounded)
    }
}

struct DASHByteRange: Equatable {
    let start: Int64
    let end: Int64

    init?(start: Int64, end: Int64) {
        guard start >= 0, end >= start else { return nil }
        self.start = start
        self.end = end
    }

    init?(_ value: String?) {
        guard let value else { return nil }
        let parts = value.trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int64(parts[0]),
              let end = Int64(parts[1]),
              start >= 0,
              end >= start else {
            return nil
        }
        self.start = start
        self.end = end
    }

    var headerValue: String { "bytes=\(start)-\(end)" }
}

private struct DASHSegmentResource {
    var path: String?
    var byteRange: DASHByteRange?
}

private struct SegmentList {
    var initialization: DASHSegmentResource?
    var segments: [DASHSegmentResource] = []
}

private struct SegmentBase {
    var initialization: DASHSegmentResource?
    var indexResource: DASHSegmentResource?
    var indexRange: DASHByteRange?
}

private struct TimelineSegment {
    var start: Int64?
    var duration: Int64
    var repeatCount: Int
}

private struct SegmentRef {
    var number: Int
    var time: Int64?
}

struct DASHSIDXReference: Equatable {
    let byteRange: DASHByteRange
    let duration: UInt32
}

struct DASHSIDX: Equatable {
    let boxRange: DASHByteRange
    let timescale: UInt32
    let references: [DASHSIDXReference]
}

enum DASHSIDXParser {
    private static let maximumReferenceCount = 100_000

    static func parse(data: Data, absoluteDataOffset: Int64 = 0) throws -> DASHSIDX {
        guard absoluteDataOffset >= 0, data.count >= 8 else {
            throw failure("DASH SIDX data is too short.")
        }

        var lastError: Error?
        for typeOffset in 4..<(data.count - 3) where isSIDXType(data, offset: typeOffset) {
            let boxStart = typeOffset - 4
            do {
                return try parseBox(data: data, boxStart: boxStart, absoluteDataOffset: absoluteDataOffset)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? failure("DASH SegmentBase index did not contain a SIDX box.")
    }

    private static func parseBox(data: Data, boxStart: Int, absoluteDataOffset: Int64) throws -> DASHSIDX {
        guard let size32 = readUInt32(data, at: boxStart) else {
            throw failure("DASH SIDX box header is truncated.")
        }

        let headerSize: Int
        let boxSize: Int
        if size32 == 1 {
            guard let extendedSize = readUInt64(data, at: boxStart + 8),
                  extendedSize >= 16,
                  extendedSize <= UInt64(Int.max) else {
                throw failure("DASH SIDX extended size is invalid.")
            }
            headerSize = 16
            boxSize = Int(extendedSize)
        } else if size32 == 0 {
            headerSize = 8
            boxSize = data.count - boxStart
        } else {
            headerSize = 8
            boxSize = Int(size32)
        }

        guard boxSize >= headerSize,
              boxStart >= 0,
              boxStart <= data.count - boxSize else {
            throw failure("DASH SIDX box extends beyond the received index range.")
        }

        var cursor = boxStart + headerSize
        guard cursor <= data.count - 4 else {
            throw failure("DASH SIDX full-box header is truncated.")
        }
        let version = data[cursor]
        cursor += 4
        guard version == 0 || version == 1,
              readUInt32(data, at: cursor) != nil,
              let timescale = readUInt32(data, at: cursor + 4),
              timescale > 0 else {
            throw failure("DASH SIDX version or timescale is invalid.")
        }
        cursor += 8

        let firstOffset: UInt64
        if version == 0 {
            guard readUInt32(data, at: cursor) != nil,
                  let value = readUInt32(data, at: cursor + 4) else {
                throw failure("DASH SIDX timing fields are truncated.")
            }
            firstOffset = UInt64(value)
            cursor += 8
        } else {
            guard readUInt64(data, at: cursor) != nil,
                  let value = readUInt64(data, at: cursor + 8) else {
                throw failure("DASH SIDX timing fields are truncated.")
            }
            firstOffset = value
            cursor += 16
        }

        guard readUInt16(data, at: cursor) != nil,
              let referenceCountValue = readUInt16(data, at: cursor + 2) else {
            throw failure("DASH SIDX reference header is truncated.")
        }
        cursor += 4
        let referenceCount = Int(referenceCountValue)
        guard referenceCount > 0,
              referenceCount <= maximumReferenceCount,
              cursor <= boxStart + boxSize - referenceCount * 12 else {
            throw failure("DASH SIDX reference count is invalid.")
        }

        let (absoluteBoxStart, startOverflow) = absoluteDataOffset.addingReportingOverflow(Int64(boxStart))
        let (absoluteBoxEnd, endOverflow) = absoluteBoxStart.addingReportingOverflow(Int64(boxSize))
        guard !startOverflow, !endOverflow,
              let firstOffsetValue = Int64(exactly: firstOffset) else {
            throw failure("DASH SIDX absolute offset overflowed.")
        }
        let (firstReferenceStart, firstOverflow) = absoluteBoxEnd.addingReportingOverflow(firstOffsetValue)
        guard !firstOverflow,
              let boxRange = DASHByteRange(start: absoluteBoxStart, end: absoluteBoxEnd - 1) else {
            throw failure("DASH SIDX absolute range is invalid.")
        }

        var references: [DASHSIDXReference] = []
        references.reserveCapacity(referenceCount)
        var referenceStart = firstReferenceStart
        for _ in 0..<referenceCount {
            guard let referenceInfo = readUInt32(data, at: cursor),
                  let duration = readUInt32(data, at: cursor + 4),
                  readUInt32(data, at: cursor + 8) != nil else {
                throw failure("DASH SIDX reference entry is truncated.")
            }
            cursor += 12

            let referenceType = referenceInfo >> 31
            let referencedSize = Int64(referenceInfo & 0x7fff_ffff)
            guard referenceType == 0 else {
                throw failure("Hierarchical DASH SIDX references are not supported.")
            }
            guard referencedSize > 0 else {
                throw failure("DASH SIDX contains an empty media reference.")
            }
            let (nextStart, overflowed) = referenceStart.addingReportingOverflow(referencedSize)
            guard !overflowed,
                  let byteRange = DASHByteRange(start: referenceStart, end: nextStart - 1) else {
                throw failure("DASH SIDX media range overflowed.")
            }
            references.append(DASHSIDXReference(byteRange: byteRange, duration: duration))
            referenceStart = nextStart
        }

        return DASHSIDX(boxRange: boxRange, timescale: timescale, references: references)
    }

    private static func isSIDXType(_ data: Data, offset: Int) -> Bool {
        guard offset >= 0, offset <= data.count - 4 else { return false }
        return data[offset] == 0x73 && data[offset + 1] == 0x69 &&
            data[offset + 2] == 0x64 && data[offset + 3] == 0x78
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard let high = readUInt32(data, at: offset),
              let low = readUInt32(data, at: offset + 4) else {
            return nil
        }
        return (UInt64(high) << 32) | UInt64(low)
    }

    private static func failure(_ message: String) -> NativeDownloadError {
        .unsupported(message)
    }
}

private final class MPDParser: NSObject, XMLParserDelegate {
    private enum SegmentScope {
        case mpd
        case period
        case adaptation
        case representation
    }

    private var manifest = MPDManifest(mediaPresentationDuration: nil, representations: [])
    private var baseStack: [String] = [""]
    private var textBuffer = ""
    private var currentRepresentation: MPDRepresentation?
    private var currentPeriodDuration: Double?
    private var adaptationMimeType = ""
    private var adaptationIsProtected = false
    private var inPeriod = false
    private var inAdaptation = false

    private var mpdTemplate: SegmentTemplate?
    private var periodTemplate: SegmentTemplate?
    private var adaptationTemplate: SegmentTemplate?
    private var mpdList: SegmentList?
    private var periodList: SegmentList?
    private var adaptationList: SegmentList?
    private var mpdSegmentBase: SegmentBase?
    private var periodSegmentBase: SegmentBase?
    private var adaptationSegmentBase: SegmentBase?

    private var activeTemplateScope: SegmentScope?
    private var activeListScope: SegmentScope?
    private var activeSegmentBaseScope: SegmentScope?
    private var inSegmentTimeline = false
    private var listHasExplicitSegments = false

    static func parse(_ xml: String) throws -> MPDManifest {
        guard let data = xml.data(using: .utf8) else {
            throw NativeDownloadError.invalidPlaylist
        }
        let delegate = MPDParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw NativeDownloadError.invalidPlaylist
        }
        return delegate.manifest
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        textBuffer = ""
        let element = Self.localName(elementName)

        if Self.inheritsBasePath(element) {
            baseStack.append(baseStack.last ?? "")
        }

        switch element {
        case "MPD":
            manifest.mediaPresentationDuration = parseDuration(attributeDict["mediaPresentationDuration"])
        case "Period":
            inPeriod = true
            currentPeriodDuration = parseDuration(attributeDict["duration"]) ?? manifest.mediaPresentationDuration
            periodTemplate = mpdTemplate
            periodList = mpdList
            periodSegmentBase = mpdSegmentBase
        case "AdaptationSet":
            inAdaptation = true
            adaptationMimeType = attributeDict["mimeType"] ?? attributeDict["contentType"] ?? ""
            adaptationIsProtected = false
            adaptationTemplate = periodTemplate
            adaptationList = periodList
            adaptationSegmentBase = periodSegmentBase
        case "Representation":
            let mime = attributeDict["mimeType"] ?? attributeDict["contentType"] ?? adaptationMimeType
            currentRepresentation = MPDRepresentation(
                id: attributeDict["id"] ?? "representation",
                bandwidth: Int(attributeDict["bandwidth"] ?? "") ?? 0,
                mimeType: mime,
                basePath: baseStack.last ?? "",
                mediaPresentationDuration: currentPeriodDuration ?? manifest.mediaPresentationDuration,
                template: adaptationTemplate,
                list: adaptationList,
                segmentBase: adaptationSegmentBase,
                isProtected: adaptationIsProtected
            )
        case "ContentProtection":
            if currentRepresentation != nil {
                currentRepresentation?.isProtected = true
            } else if inAdaptation {
                adaptationIsProtected = true
            }
        case "SegmentTemplate":
            let scope = currentSegmentScope()
            var template = template(for: scope) ?? SegmentTemplate()
            if let value = attributeDict["initialization"] { template.initialization = value }
            if let value = attributeDict["media"] { template.media = value }
            if let value = attributeDict["startNumber"].flatMap(Int.init) { template.startNumber = value }
            if let value = attributeDict["timescale"].flatMap(Int.init) { template.timescale = value }
            if let value = attributeDict["duration"].flatMap(Int64.init) { template.duration = value }
            if let value = attributeDict["presentationTimeOffset"].flatMap(Int64.init) {
                template.presentationTimeOffset = value
            }
            setTemplate(template, for: scope)
            setList(nil, for: scope)
            setSegmentBase(nil, for: scope)
            activeTemplateScope = scope
        case "SegmentTimeline":
            guard let scope = activeTemplateScope else { return }
            updateTemplate(for: scope) { $0.timeline = [] }
            inSegmentTimeline = true
        case "S":
            guard inSegmentTimeline, let scope = activeTemplateScope else { return }
            let segment = TimelineSegment(
                start: attributeDict["t"].flatMap(Int64.init),
                duration: Int64(attributeDict["d"] ?? "") ?? 0,
                repeatCount: Int(attributeDict["r"] ?? "") ?? 0
            )
            guard segment.duration > 0 else { return }
            updateTemplate(for: scope) { $0.timeline.append(segment) }
        case "SegmentList":
            let scope = currentSegmentScope()
            setList(list(for: scope) ?? SegmentList(), for: scope)
            setTemplate(nil, for: scope)
            setSegmentBase(nil, for: scope)
            activeListScope = scope
            listHasExplicitSegments = false
        case "SegmentBase":
            let scope = currentSegmentScope()
            var value = segmentBase(for: scope) ?? SegmentBase()
            if let range = DASHByteRange(attributeDict["indexRange"]) {
                value.indexRange = range
                if value.indexResource != nil {
                    value.indexResource?.byteRange = range
                }
            }
            setSegmentBase(value, for: scope)
            setTemplate(nil, for: scope)
            setList(nil, for: scope)
            activeSegmentBaseScope = scope
        case "Initialization":
            let resource = DASHSegmentResource(
                path: attributeDict["sourceURL"].dashNonEmpty,
                byteRange: DASHByteRange(attributeDict["range"])
            )
            if let scope = activeListScope {
                updateList(for: scope) { $0.initialization = resource }
            } else if let scope = activeSegmentBaseScope {
                updateSegmentBase(for: scope) { $0.initialization = resource }
            }
        case "SegmentURL":
            guard let scope = activeListScope else { return }
            let resource = DASHSegmentResource(
                path: attributeDict["media"].dashNonEmpty,
                byteRange: DASHByteRange(attributeDict["mediaRange"])
            )
            guard resource.path != nil || resource.byteRange != nil else { return }
            updateList(for: scope) { list in
                if !listHasExplicitSegments {
                    list.segments.removeAll()
                    listHasExplicitSegments = true
                }
                list.segments.append(resource)
            }
        case "RepresentationIndex":
            guard let scope = activeSegmentBaseScope else { return }
            let inheritedRange = segmentBase(for: scope)?.indexRange
            let resource = DASHSegmentResource(
                path: attributeDict["sourceURL"].dashNonEmpty,
                byteRange: DASHByteRange(attributeDict["range"]) ?? inheritedRange
            )
            updateSegmentBase(for: scope) { $0.indexResource = resource }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = Self.localName(elementName)
        switch element {
        case "BaseURL":
            let base = textBuffer.trimmed
            if !base.isEmpty {
                let combined = Self.combinedBasePath(baseStack.last ?? "", base)
                baseStack[baseStack.count - 1] = combined
                currentRepresentation?.basePath = combined
            }
        case "Representation":
            if let representation = currentRepresentation {
                manifest.representations.append(representation)
            }
            currentRepresentation = nil
            popBasePath()
        case "AdaptationSet":
            inAdaptation = false
            adaptationMimeType = ""
            adaptationIsProtected = false
            adaptationTemplate = nil
            adaptationList = nil
            adaptationSegmentBase = nil
            popBasePath()
        case "Period":
            inPeriod = false
            currentPeriodDuration = nil
            periodTemplate = nil
            periodList = nil
            periodSegmentBase = nil
            popBasePath()
        case "MPD":
            popBasePath()
        case "SegmentTimeline":
            inSegmentTimeline = false
        case "SegmentTemplate":
            activeTemplateScope = nil
        case "SegmentList":
            activeListScope = nil
            listHasExplicitSegments = false
        case "SegmentBase":
            activeSegmentBaseScope = nil
        default:
            break
        }
        textBuffer = ""
    }

    private func currentSegmentScope() -> SegmentScope {
        if currentRepresentation != nil { return .representation }
        if inAdaptation { return .adaptation }
        if inPeriod { return .period }
        return .mpd
    }

    private func template(for scope: SegmentScope) -> SegmentTemplate? {
        switch scope {
        case .mpd: return mpdTemplate
        case .period: return periodTemplate
        case .adaptation: return adaptationTemplate
        case .representation: return currentRepresentation?.template
        }
    }

    private func setTemplate(_ value: SegmentTemplate?, for scope: SegmentScope) {
        switch scope {
        case .mpd: mpdTemplate = value
        case .period: periodTemplate = value
        case .adaptation: adaptationTemplate = value
        case .representation: currentRepresentation?.template = value
        }
    }

    private func updateTemplate(for scope: SegmentScope, _ update: (inout SegmentTemplate) -> Void) {
        var value = template(for: scope) ?? SegmentTemplate()
        update(&value)
        setTemplate(value, for: scope)
    }

    private func list(for scope: SegmentScope) -> SegmentList? {
        switch scope {
        case .mpd: return mpdList
        case .period: return periodList
        case .adaptation: return adaptationList
        case .representation: return currentRepresentation?.list
        }
    }

    private func setList(_ value: SegmentList?, for scope: SegmentScope) {
        switch scope {
        case .mpd: mpdList = value
        case .period: periodList = value
        case .adaptation: adaptationList = value
        case .representation: currentRepresentation?.list = value
        }
    }

    private func updateList(for scope: SegmentScope, _ update: (inout SegmentList) -> Void) {
        var value = list(for: scope) ?? SegmentList()
        update(&value)
        setList(value, for: scope)
    }

    private func segmentBase(for scope: SegmentScope) -> SegmentBase? {
        switch scope {
        case .mpd: return mpdSegmentBase
        case .period: return periodSegmentBase
        case .adaptation: return adaptationSegmentBase
        case .representation: return currentRepresentation?.segmentBase
        }
    }

    private func setSegmentBase(_ value: SegmentBase?, for scope: SegmentScope) {
        switch scope {
        case .mpd: mpdSegmentBase = value
        case .period: periodSegmentBase = value
        case .adaptation: adaptationSegmentBase = value
        case .representation: currentRepresentation?.segmentBase = value
        }
    }

    private func updateSegmentBase(for scope: SegmentScope, _ update: (inout SegmentBase) -> Void) {
        var value = segmentBase(for: scope) ?? SegmentBase()
        update(&value)
        setSegmentBase(value, for: scope)
    }

    private func parseDuration(_ value: String?) -> Double? {
        guard let value else { return nil }
        let pattern = #"^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else {
            return nil
        }

        func part(_ index: Int) -> Double {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value) else {
                return 0
            }
            return Double(value[range]) ?? 0
        }

        let duration = part(1) * 86_400 + part(2) * 3_600 + part(3) * 60 + part(4)
        return duration > 0 ? duration : nil
    }

    private static func inheritsBasePath(_ elementName: String) -> Bool {
        elementName == "MPD" || elementName == "Period" || elementName == "AdaptationSet" || elementName == "Representation"
    }

    private static func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private static func combinedBasePath(_ current: String, _ addition: String) -> String {
        if addition.hasPrefix("http://") || addition.hasPrefix("https://") || addition.hasPrefix("//") {
            return addition
        }
        if current.isEmpty {
            return addition
        }
        if let currentURL = URL(string: current),
           currentURL.scheme != nil,
           let combined = URL(string: addition, relativeTo: currentURL)?.absoluteURL {
            return combined.absoluteString
        }
        if addition.hasPrefix("/") || current.hasSuffix("/") {
            return current + addition
        }
        return current + "/" + addition
    }

    private func popBasePath() {
        if baseStack.count > 1 {
            _ = baseStack.popLast()
        }
    }
}

private extension URL {
    func pathExtensionOr(_ fallback: String) -> String {
        pathExtension.isEmpty ? fallback : pathExtension
    }
}

private extension Optional where Wrapped == String {
    var dashNonEmpty: String? {
        guard let value = self?.trimmed, !value.isEmpty else { return nil }
        return value
    }
}
