import Foundation

final class SiteRequestHeaderService {
    func requestOptions(
        for url: URL,
        explicitReferer: String? = nil,
        siteRules: [SiteRule]
    ) -> HTTPRequestOptions {
        var referer = explicitReferer?.trimmed
        var userAgent: String?

        if let rule = matchingHeaderRule(for: url, siteRules: siteRules) {
            if let template = rule.refererTemplate?.trimmed,
               !template.isEmpty {
                let expanded = expandedHeaderTemplate(
                    template,
                    url: url
                ).trimmed
                if !expanded.isEmpty {
                    referer = expanded
                }
            }

            if let value = rule.userAgent?.trimmed, !value.isEmpty {
                userAgent = value
            }
        }

        return HTTPRequestOptions(
            referer: (referer?.isEmpty ?? true) ? nil : referer,
            userAgent: (userAgent?.isEmpty ?? true) ? nil : userAgent
        )
    }

    func applyingHeaderRules(
        to resolved: ResolvedDownload,
        siteRules: [SiteRule]
    ) -> ResolvedDownload {
        let assets = resolved.assets.map {
            applyingHeaderRules(to: $0, siteRules: siteRules)
        }
        let packageMode: DownloadPackageMode

        switch resolved.packageMode {
        case .files:
            packageMode = .files
        case .concatenate(let outputFilename):
            packageMode = .concatenate(
                outputFilename: outputFilename
            )
        case .mux(
            let videoAssets,
            let audioAssets,
            let outputFilename
        ):
            packageMode = .mux(
                videoAssets: videoAssets.map {
                    applyingHeaderRules(
                        to: $0,
                        siteRules: siteRules
                    )
                },
                audioAssets: audioAssets.map {
                    applyingHeaderRules(
                        to: $0,
                        siteRules: siteRules
                    )
                },
                outputFilename: outputFilename
            )
        case .grouped(let fileAssetIndexes, let concatenations):
            packageMode = .grouped(
                fileAssetIndexes: fileAssetIndexes,
                concatenations: concatenations
            )
        case .groupedMedia(
            let fileAssetIndexes,
            let concatenations,
            let muxes
        ):
            packageMode = .groupedMedia(
                fileAssetIndexes: fileAssetIndexes,
                concatenations: concatenations,
                muxes: muxes
            )
        }

        return ResolvedDownload(
            title: resolved.title,
            folderName: resolved.folderName,
            assets: assets,
            packageMode: packageMode,
            metadata: resolved.metadata,
            textMergePlan: resolved.textMergePlan,
            temporaryAssetDirectories:
                resolved.temporaryAssetDirectories
        )
    }

    func applyingHeaderRules(
        to asset: ResolvedAsset,
        siteRules: [SiteRule]
    ) -> ResolvedAsset {
        var copy = asset
        let headers = requestOptions(
            for: asset.remoteURL,
            explicitReferer: asset.referer,
            siteRules: siteRules
        )
        copy.referer = headers.referer
        copy.userAgent = headers.userAgent ?? asset.userAgent
        return copy
    }

    private func matchingHeaderRule(
        for url: URL,
        siteRules: [SiteRule]
    ) -> SiteRule? {
        guard url.host != nil else { return nil }
        return siteRules
            .filter {
                !($0.refererTemplate?.trimmed.isEmpty ?? true) ||
                    !($0.userAgent?.trimmed.isEmpty ?? true)
            }
            .sorted { $0.matchSpecificity > $1.matchSpecificity }
            .first { $0.matches(url) }
    }

    private func expandedHeaderTemplate(
        _ template: String,
        url: URL
    ) -> String {
        let host = url.host ?? ""
        return template
            .replacingOccurrences(
                of: "{url}",
                with: url.absoluteString
            )
            .replacingOccurrences(of: "{host}", with: host)
            .replacingOccurrences(
                of: "{origin}",
                with: origin(for: url)
            )
            .replacingOccurrences(
                of: "{scheme}",
                with: url.scheme ?? ""
            )
            .replacingOccurrences(of: "{path}", with: url.path)
            .replacingOccurrences(
                of: "{query}",
                with: url.query ?? ""
            )
    }

    private func origin(for url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else {
            return ""
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
