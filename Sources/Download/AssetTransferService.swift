import Foundation

struct AssetTransferService {
    private let ffmpegExecutionService: FFmpegExecutionService

    init(
        ffmpegExecutionService: FFmpegExecutionService = FFmpegExecutionService()
    ) {
        self.ffmpegExecutionService = ffmpegExecutionService
    }

    func download(
        _ asset: ResolvedAsset,
        to destination: URL,
        remoteSegmentConcurrency: Int,
        progressHandler: HTTPDownloadProgressHandler? = nil
    ) async throws -> URL {
        let additionalHeaders = asset.additionalHeaderFields
        if asset.remoteURL.isFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: asset.remoteURL, to: destination)
        } else if let decryption = asset.decryption {
            let encrypted = try await HTTPClient.shared.data(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            let key = try await HTTPClient.shared.data(
                from: decryption.keyURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            let decrypted = try HLSDecrypter.decryptAES128CBC(
                data: encrypted,
                key: key,
                iv: decryption.iv
            )
            try decrypted.write(to: destination, options: .atomic)
        } else if let xorKey = asset.xorKey {
            let encrypted = try await HTTPClient.shared.data(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            let decrypted = try ComicWalkerImageDecoder.decode(encrypted, hash: xorKey)
            try decrypted.write(to: destination, options: .atomic)
        } else if let shuffle = asset.pixivGridShuffle {
            var headers = additionalHeaders
            headers["X-Cobalt-Thumber-Parameter-Gridshuffle-Key"] = shuffle.key
            let encrypted = try await HTTPClient.shared.data(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: headers
            )
            let decoded = try PixivComicImageDecoder.decode(encrypted, shuffle: shuffle)
            try decoded.write(to: destination, options: .atomic)
        } else if let shuffle = asset.lezhinImageShuffle {
            let encoded = try await HTTPClient.shared.data(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            let decoded = try LezhinImageDecoder.decode(encoded, shuffle: shuffle)
            try decoded.write(to: destination, options: .atomic)
        } else if let ugoiraPackage = asset.pixivUgoiraPackage {
            let zip = try await HTTPClient.shared.data(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            switch ugoiraPackage.outputFormat {
            case .ugoira:
                let packaged = try PixivUgoiraPackageWriter.package(
                    originalZip: zip,
                    package: ugoiraPackage
                )
                try packaged.write(to: destination, options: .atomic)
            case .gif, .webp, .png:
                try await ffmpegExecutionService.execute(
                    .pixivUgoira(
                        originalZip: zip,
                        package: ugoiraPackage,
                        output: destination
                    )
                )
            case .zip:
                try zip.write(to: destination, options: .atomic)
            }
        } else if let segmentSize = asset.metadata["remote_segment_size"].flatMap(Int64.init),
                  segmentSize > 0 {
            try await downloadRemoteSegmentedAsset(
                asset,
                to: destination,
                segmentSize: segmentSize,
                maxConcurrency: remoteSegmentConcurrency,
                additionalHeaders: additionalHeaders
            )
        } else if let rangeStart = asset.metadata["range_start"].flatMap(Int64.init),
                  let rangeEnd = asset.metadata["range_end"].flatMap(Int64.init),
                  rangeStart >= 0,
                  rangeEnd >= rangeStart,
                  additionalHeaders["Range"] != nil {
            try await downloadByteRangeAsset(
                asset,
                to: destination,
                start: rangeStart,
                end: rangeEnd,
                additionalHeaders: additionalHeaders
            )
        } else {
            return try await downloadOrdinaryAsset(
                asset,
                to: destination,
                additionalHeaders: additionalHeaders,
                progressHandler: progressHandler
            )
        }
        return destination
    }

    private func downloadOrdinaryAsset(
        _ asset: ResolvedAsset,
        to destination: URL,
        additionalHeaders: [String: String],
        progressHandler: HTTPDownloadProgressHandler? = nil
    ) async throws -> URL {
        if HitomiResolver.isLazyImageAsset(asset) {
            return try await downloadLazyHitomiAsset(
                asset,
                to: destination,
                additionalHeaders: additionalHeaders,
                progressHandler: progressHandler
            )
        }
        if EHentaiResolver.isLazyImageAsset(asset) {
            return try await downloadLazyEHentaiAsset(
                asset,
                to: destination,
                additionalHeaders: additionalHeaders
            )
        }

        var candidates: [URL] = []
        var seen = Set<String>()
        for candidate in [asset.remoteURL] + asset.alternativeRemoteURLs {
            guard seen.insert(candidate.absoluteString).inserted else { continue }
            candidates.append(candidate)
        }

        for (index, candidate) in candidates.enumerated() {
            let output = Self.alternativeAssetDestination(
                originalDestination: destination,
                originalFilename: asset.filename,
                candidateURL: candidate,
                isAlternative: index > 0
            )
            do {
                try await HTTPClient.shared.download(
                    from: candidate,
                    to: output,
                    referer: asset.referer,
                    userAgent: asset.userAgent,
                    additionalHeaders: additionalHeaders,
                    progressHandler: progressHandler
                )
                return output
            } catch NativeDownloadError.httpStatus(let status, _) where
                (status == 403 || status == 410) && index + 1 < candidates.count {
                try? FileManager.default.removeItem(at: output)
                continue
            }
        }
        throw NativeDownloadError.noFiles
    }

    private func downloadLazyHitomiAsset(
        _ asset: ResolvedAsset,
        to destination: URL,
        additionalHeaders: [String: String],
        progressHandler: HTTPDownloadProgressHandler? = nil
    ) async throws -> URL {
        let maximumAttempts = 24
        var lastError: Error?

        for attempt in 0..<maximumAttempts {
            try Task.checkCancellation()
            do {
                let resolved = try await HitomiResolver.resolveLazyImageAsset(asset)
                var headers = additionalHeaders
                for (name, value) in resolved.additionalHeaderFields {
                    headers[name] = value
                }
                try await HTTPClient.shared.download(
                    from: resolved.remoteURL,
                    to: destination,
                    referer: resolved.referer,
                    userAgent: resolved.userAgent ?? asset.userAgent,
                    additionalHeaders: headers,
                    retryLimitOverride: 0,
                    progressHandler: progressHandler
                )
                return destination
            } catch {
                try Task.checkCancellation()
                lastError = error
                guard Self.shouldRetryLazyHitomiAsset(error, attempt: attempt) else {
                    throw error
                }
                try await Self.waitBeforeLazyHitomiRetry()
            }
        }

        throw lastError ?? NativeDownloadError.noFiles
    }

    static func shouldRetryLazyHitomiAsset(_ error: Error, attempt: Int) -> Bool {
        guard attempt < 23 else { return false }
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        if let nativeError = error as? NativeDownloadError {
            switch nativeError {
            case .cancelled:
                return false
            case .httpStatus(let status, _):
                return status != 400 && status != 401
            default:
                return true
            }
        }
        return true
    }

    private static func waitBeforeLazyHitomiRetry() async throws {
#if TESTING
        return
#else
        try await Task.sleep(nanoseconds: 1_000_000_000)
#endif
    }

    private func downloadLazyEHentaiAsset(
        _ asset: ResolvedAsset,
        to destination: URL,
        additionalHeaders: [String: String]
    ) async throws -> URL {
        let maximumAttempts = 24
        var lastError: Error?

        for attempt in 0..<maximumAttempts {
            try Task.checkCancellation()
            do {
                let resolved = try await EHentaiResolver.resolveLazyImageAsset(asset)
                let output = Self.lazyEHentaiDestination(
                    destination,
                    placeholderFilename: asset.filename,
                    resolvedFilename: resolved.filename
                )
                var headers = additionalHeaders
                for (name, value) in resolved.additionalHeaderFields {
                    headers[name] = value
                }
                try await HTTPClient.shared.download(
                    from: resolved.remoteURL,
                    to: output,
                    referer: resolved.referer,
                    userAgent: resolved.userAgent ?? asset.userAgent,
                    additionalHeaders: headers,
                    retryLimitOverride: 0
                )
                return output
            } catch {
                try Task.checkCancellation()
                lastError = error
                if !Self.shouldRetryLazyEHentaiAsset(error, attempt: attempt) {
                    throw error
                }
            }
        }

        throw lastError ?? NativeDownloadError.noFiles
    }

    static func lazyEHentaiDestination(
        _ destination: URL,
        placeholderFilename: String,
        resolvedFilename: String
    ) -> URL {
        let placeholderExtension = (placeholderFilename as NSString).pathExtension.lowercased()
        let resolvedExtension = (resolvedFilename as NSString).pathExtension.lowercased()
        guard !resolvedExtension.isEmpty,
              resolvedExtension != placeholderExtension,
              resolvedExtension.range(
                of: #"^[a-z0-9]{1,8}$"#,
                options: .regularExpression
              ) != nil else {
            return destination
        }
        return destination.deletingPathExtension().appendingPathExtension(resolvedExtension)
    }

    static func shouldRetryLazyEHentaiAsset(_ error: Error, attempt: Int) -> Bool {
        guard attempt < 23 else { return false }
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        if let nativeError = error as? NativeDownloadError {
            switch nativeError {
            case .cancelled:
                return false
            case .httpStatus(let status, _):
                if status == 401 { return false }
                if status == 404 { return attempt < 3 }
                if status == 403 { return attempt < 7 }
                return status == 408 || status == 429 || status >= 500
            default:
                return true
            }
        }
        return true
    }

    static func alternativeAssetDestination(
        originalDestination: URL,
        originalFilename: String,
        candidateURL: URL,
        isAlternative: Bool
    ) -> URL {
        guard isAlternative else { return originalDestination }
        let originalExtension = (originalFilename as NSString).pathExtension.lowercased()
        let destinationExtension = originalDestination.pathExtension.lowercased()
        let candidateExtension = candidateURL.pathExtension.lowercased()
        guard !candidateExtension.isEmpty,
              candidateExtension.range(
                of: #"^[a-z0-9]{1,8}$"#,
                options: .regularExpression
              ) != nil,
              destinationExtension == originalExtension,
              candidateExtension != destinationExtension else {
            return originalDestination
        }
        let candidate = originalDestination
            .deletingPathExtension()
            .appendingPathExtension(candidateExtension)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return AppPaths.uniqueFileURL(
                in: candidate.deletingLastPathComponent(),
                filename: candidate.lastPathComponent
            )
        }
        return candidate
    }

    private func downloadRemoteSegmentedAsset(
        _ asset: ResolvedAsset,
        to destination: URL,
        segmentSize: Int64,
        maxConcurrency: Int,
        additionalHeaders: [String: String]
    ) async throws {
        try Task.checkCancellation()
        guard let totalLength = try await remoteSegmentedContentLength(
            for: asset,
            additionalHeaders: additionalHeaders
        ) else {
            try await HTTPClient.shared.download(
                from: asset.remoteURL,
                to: destination,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            return
        }

        let ranges = Self.remoteSegmentRanges(
            totalLength: totalLength,
            segmentSize: segmentSize
        )
        guard ranges.count > 1 else {
            try await HTTPClient.shared.download(
                from: asset.remoteURL,
                to: destination,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: additionalHeaders
            )
            return
        }

        let partFolder = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent)-segments-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: partFolder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: partFolder) }

        let workerCount = min(max(1, maxConcurrency), ranges.count)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for workerIndex in 0..<workerCount {
                group.addTask {
                    for partIndex in stride(
                        from: workerIndex,
                        to: ranges.count,
                        by: workerCount
                    ) {
                        try Task.checkCancellation()
                        let range = ranges[partIndex]
                        var headers = additionalHeaders
                        headers["Range"] = "bytes=\(range.start)-\(range.end)"
                        let partURL = partFolder.appendingPathComponent(
                            String(format: "%08d.part", partIndex)
                        )
                        try await downloadByteRangeAsset(
                            asset,
                            to: partURL,
                            start: range.start,
                            end: range.end,
                            additionalHeaders: headers
                        )
                    }
                }
            }
            try await group.waitForAll()
        }

        let assembled = partFolder.appendingPathComponent("assembled.tmp")
        FileManager.default.createFile(atPath: assembled.path, contents: nil)
        let writer = try FileHandle(forWritingTo: assembled)
        do {
            defer { try? writer.close() }
            for partIndex in ranges.indices {
                try Task.checkCancellation()
                let partURL = partFolder.appendingPathComponent(
                    String(format: "%08d.part", partIndex)
                )
                let reader = try FileHandle(forReadingFrom: partURL)
                do {
                    defer { try? reader.close() }
                    while let chunk = try reader.read(upToCount: 1_048_576),
                          !chunk.isEmpty {
                        try writer.write(contentsOf: chunk)
                    }
                }
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: assembled, to: destination)
    }

    private func remoteSegmentedContentLength(
        for asset: ResolvedAsset,
        additionalHeaders: [String: String]
    ) async throws -> Int64? {
        var probeHeaders = additionalHeaders
        probeHeaders["Range"] = "bytes=0-0"
        let response: HTTPURLResponse
        do {
            guard let value = try await HTTPClient.shared.head(
                from: asset.remoteURL,
                referer: asset.referer,
                userAgent: asset.userAgent,
                additionalHeaders: probeHeaders
            ) else {
                return nil
            }
            response = value
        } catch {
            try Task.checkCancellation()
            return nil
        }

        if response.statusCode == 206,
           let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let total = Self.contentRangeTotalLength(contentRange) {
            return total
        }
        guard response.value(forHTTPHeaderField: "Accept-Ranges")?
            .lowercased()
            .contains("bytes") == true else {
            return nil
        }
        if let rawLength = response.value(forHTTPHeaderField: "Content-Length"),
           let total = Int64(rawLength),
           total > 0 {
            return total
        }
        return response.expectedContentLength > 0
            ? response.expectedContentLength
            : nil
    }

    static func remoteSegmentRanges(
        totalLength: Int64,
        segmentSize: Int64
    ) -> [(start: Int64, end: Int64)] {
        guard totalLength > 0, segmentSize > 0 else { return [] }
        var ranges: [(start: Int64, end: Int64)] = []
        var start: Int64 = 0
        while start < totalLength {
            let remaining = totalLength - start
            let length = min(segmentSize, remaining)
            ranges.append((start, start + length - 1))
            start += length
        }
        return ranges
    }

    private static func contentRangeTotalLength(_ raw: String) -> Int64? {
        guard let slash = raw.lastIndex(of: "/") else { return nil }
        let value = raw[raw.index(after: slash)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != "*", let total = Int64(value), total > 0 else { return nil }
        return total
    }

    private func downloadByteRangeAsset(
        _ asset: ResolvedAsset,
        to destination: URL,
        start: Int64,
        end: Int64,
        additionalHeaders: [String: String]
    ) async throws {
        let (distance, distanceOverflowed) = end.subtractingReportingOverflow(start)
        let (expectedLength, lengthOverflowed) = distance.addingReportingOverflow(1)
        guard !distanceOverflowed, !lengthOverflowed, expectedLength > 0 else {
            throw NativeDownloadError.unsupported("Byte-range length overflowed.")
        }
        let download = try await HTTPClient.shared.downloadTemporary(
            from: asset.remoteURL,
            referer: asset.referer,
            userAgent: asset.userAgent,
            additionalHeaders: additionalHeaders
        )
        var movedTemporary = false
        defer {
            if !movedTemporary {
                try? FileManager.default.removeItem(at: download.fileURL)
            }
        }

        guard let response = download.response else {
            throw NativeDownloadError.unsupported(
                "Byte-range download returned no HTTP response."
            )
        }
        let downloadedSize = Int64(
            (try download.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )

        if response.statusCode == 206 {
            guard downloadedSize == expectedLength else {
                throw NativeDownloadError.unsupported(
                    "Byte-range response length was \(downloadedSize), expected \(expectedLength)."
                )
            }
            if let contentRange = response.value(
                forHTTPHeaderField: "Content-Range"
            )?.lowercased(),
               !contentRange.hasPrefix("bytes \(start)-\(end)/") {
                throw NativeDownloadError.unsupported(
                    "Byte-range response did not match the requested offsets."
                )
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: download.fileURL, to: destination)
            movedTemporary = true
            return
        }

        guard response.statusCode == 200,
              downloadedSize > end else {
            throw NativeDownloadError.unsupported(
                "Server ignored the byte range without returning enough source data."
            )
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        do {
            let reader = try FileHandle(forReadingFrom: download.fileURL)
            let writer = try FileHandle(forWritingTo: destination)
            defer {
                try? reader.close()
                try? writer.close()
            }
            try reader.seek(toOffset: UInt64(start))
            var remaining = expectedLength
            while remaining > 0 {
                let requestCount = Int(min(remaining, 1_048_576))
                guard let chunk = try reader.read(upToCount: requestCount),
                      !chunk.isEmpty else {
                    throw NativeDownloadError.unsupported(
                        "Byte-range source ended before the requested offset range."
                    )
                }
                try writer.write(contentsOf: chunk)
                remaining -= Int64(chunk.count)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
