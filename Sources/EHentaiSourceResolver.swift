import Foundation

enum EHentaiSelectedSource: String {
    case hitomi
    case original
}

struct EHentaiSourceResolution {
    var download: ResolvedDownload
    var sourceURL: URL
    var selectedSource: EHentaiSelectedSource
    var usedFallback: Bool
}

@MainActor
final class EHentaiSourceResolver {
    private let hitomiResolver: HitomiResolver
    private let eHentaiResolver: EHentaiResolver
    private let maximumSourceCycles = 8
#if TESTING
    private let sourceRetryDelayNanoseconds: UInt64 = 0
#else
    private let sourceRetryDelayNanoseconds: UInt64 = 500_000_000
#endif

    init(hitomiResolver: HitomiResolver, eHentaiResolver: EHentaiResolver) {
        self.hitomiResolver = hitomiResolver
        self.eHentaiResolver = eHentaiResolver
    }

    func resolve(
        _ sourceURL: URL,
        mode: EHentaiSourceMode,
        preferWebP: Bool,
        headers: HTTPRequestOptions,
        preferOriginalImages: Bool,
        preferJapaneseTitle: Bool = false,
        onFallbackToOriginal: (() -> Void)? = nil,
        onStage: ((String) -> Void)? = nil
    ) async throws -> EHentaiSourceResolution {
        guard let gallery = EHentaiResolver.galleryID(from: sourceURL),
              let hitomiURL = HitomiResolver.canonicalGalleryURL(galleryID: gallery.id) else {
            let download = try await resolveOriginal(
                sourceURL,
                mode: mode,
                headers: headers,
                preferOriginalImages: preferOriginalImages,
                preferJapaneseTitle: preferJapaneseTitle,
                hitomiURL: nil,
                hitomiError: nil,
                usedFallback: false
            )
            return EHentaiSourceResolution(
                download: download,
                sourceURL: sourceURL,
                selectedSource: .original,
                usedFallback: false
            )
        }

        let originalCandidates = Self.originalSourceCandidates(sourceURL)
        var lastError: Error?
        var lastHitomiError: Error?
        var reportedFallback = false

        for cycle in 0..<maximumSourceCycles {
            try Task.checkCancellation()

            if mode != .original {
                onStage?("Checking Hitomi mirror (\(cycle + 1)/\(maximumSourceCycles))")
                do {
                    var download = try await hitomiResolver.resolve(hitomiURL, preferWebP: preferWebP)
                    download.metadata = Self.sourceMetadata(
                        download.metadata,
                        originalURL: sourceURL,
                        selectedURL: hitomiURL,
                        hitomiURL: hitomiURL,
                        mode: mode,
                        selectedSource: .hitomi,
                        hitomiError: lastHitomiError,
                        usedFallback: false
                    )
                    download.metadata["source_attempt_cycle"] = String(cycle + 1)
                    return EHentaiSourceResolution(
                        download: download,
                        sourceURL: hitomiURL,
                        selectedSource: .hitomi,
                        usedFallback: false
                    )
                } catch {
                    try Self.rethrowIfCancelled(error)
                    lastError = error
                    lastHitomiError = error
                }
            }

            let shouldTryOriginal = mode == .original || (mode == .automatic && cycle > 0)
            if shouldTryOriginal {
                if mode == .automatic, !reportedFallback {
                    reportedFallback = true
                    onFallbackToOriginal?()
                }
                let candidateIndex = mode == .original ? cycle : cycle - 1
                let candidate = originalCandidates[candidateIndex % originalCandidates.count]
                onStage?("Reading \(Self.originalSourceLabel(candidate)) (\(cycle + 1)/\(maximumSourceCycles))")
                do {
                    var download = try await resolveOriginal(
                        candidate,
                        submittedSourceURL: sourceURL,
                        mode: mode,
                        headers: headers,
                        preferOriginalImages: preferOriginalImages,
                        preferJapaneseTitle: preferJapaneseTitle,
                        hitomiURL: hitomiURL,
                        hitomiError: lastHitomiError,
                        usedFallback: mode == .automatic
                    )
                    download.metadata["source_attempt_cycle"] = String(cycle + 1)
                    return EHentaiSourceResolution(
                        download: download,
                        sourceURL: candidate,
                        selectedSource: .original,
                        usedFallback: mode == .automatic
                    )
                } catch {
                    try Self.rethrowIfCancelled(error)
                    lastError = error
                }
            }

            if cycle + 1 < maximumSourceCycles, sourceRetryDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: sourceRetryDelayNanoseconds)
            }
        }

        throw lastError ?? NativeDownloadError.noFiles
    }

    private func resolveOriginal(
        _ sourceURL: URL,
        submittedSourceURL: URL? = nil,
        mode: EHentaiSourceMode,
        headers: HTTPRequestOptions,
        preferOriginalImages: Bool,
        preferJapaneseTitle: Bool,
        hitomiURL: URL?,
        hitomiError: Error?,
        usedFallback: Bool
    ) async throws -> ResolvedDownload {
        var download = try await eHentaiResolver.resolve(
            sourceURL,
            headers: headers,
            preferOriginal: preferOriginalImages,
            preferJapaneseTitle: preferJapaneseTitle
        )
        download.metadata = Self.sourceMetadata(
            download.metadata,
            originalURL: submittedSourceURL ?? sourceURL,
            selectedURL: sourceURL,
            hitomiURL: hitomiURL,
            mode: mode,
            selectedSource: .original,
            hitomiError: hitomiError,
            usedFallback: usedFallback
        )
        return download
    }

    private nonisolated static func originalSourceCandidates(_ sourceURL: URL) -> [URL] {
        let host = sourceURL.host?.lowercased() ?? ""
        guard !host.contains("exhentai"),
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return [sourceURL]
        }

        if host == "e-hentai.org" || host == "www.e-hentai.org" {
            components.host = "exhentai.org"
        } else if host == "e-hentai.test" || host.hasSuffix(".e-hentai.test") {
            components.host = "exhentai.test"
        } else {
            return [sourceURL]
        }
        guard let alternate = components.url, alternate != sourceURL else {
            return [sourceURL]
        }
        return [sourceURL, alternate]
    }

    private nonisolated static func originalSourceLabel(_ url: URL) -> String {
        url.host?.lowercased().contains("exhentai") == true ? "ExHentai gallery" : "E-Hentai gallery"
    }

    private nonisolated static func sourceMetadata(
        _ metadata: [String: String],
        originalURL: URL,
        selectedURL: URL,
        hitomiURL: URL?,
        mode: EHentaiSourceMode,
        selectedSource: EHentaiSelectedSource,
        hitomiError: Error?,
        usedFallback: Bool
    ) -> [String: String] {
        var result = metadata
        result["submitted_source_url"] = originalURL.absoluteString
        result["selected_source_url"] = selectedURL.absoluteString
        result["source_selection_mode"] = mode.rawValue
        result["source_selected"] = selectedSource.rawValue
        result["source_priority"] = mode == .automatic ? "hitomi,ehen" : selectedSource.rawValue
        result["source_fallback"] = usedFallback ? "true" : "false"
        if let hitomiURL {
            result["hitomi_mirror_url"] = hitomiURL.absoluteString
        }
        if let hitomiError {
            result["hitomi_lookup_error"] = String(hitomiError.localizedDescription.prefix(500))
        }
        return DownloadMetadata.clean(result)
    }

    private nonisolated static func rethrowIfCancelled(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError {
            throw CancellationError()
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            throw CancellationError()
        }
        if let nativeError = error as? NativeDownloadError,
           case .cancelled = nativeError {
            throw CancellationError()
        }
    }
}
