import Foundation

@MainActor
final class SearchUICommandFacade {
    let sourceLinkCommandService: SourceLinkCommandService
    let clipboardCommandService: ClipboardCommandService
    let outputCommandService: OutputCommandService

    init(
        sourceLinkCommandService: SourceLinkCommandService,
        clipboardCommandService: ClipboardCommandService,
        outputCommandService: OutputCommandService
    ) {
        self.sourceLinkCommandService = sourceLinkCommandService
        self.clipboardCommandService = clipboardCommandService
        self.outputCommandService = outputCommandService
    }

    func openSearchURL(_ url: URL) {
        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
    }

    func openResult(
        _ result: SearchResultLink
    ) -> String? {
        guard let url = Self.browserURL(for: result) else {
            return "No browser URL"
        }
        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
        return nil
    }

    func copyResultURL(
        _ result: SearchResultLink
    ) -> String {
        guard Self.browserURL(for: result) != nil else {
            return "No browser URL"
        }
        return clipboardCommandService.copyText(result.url)
            ? "URL copied"
            : "Copy failed"
    }

    func copyResultTitle(
        _ result: SearchResultLink
    ) -> String {
        guard let title = Self.copyTitle(for: result) else {
            return "No title"
        }
        return clipboardCommandService.copyText(title)
            ? "Title copied"
            : "Copy failed"
    }

    func copyMetadata(
        label: String,
        value: String
    ) -> String {
        let value = value.trimmed
        guard !value.isEmpty else {
            return "No \(label.lowercased())"
        }
        return clipboardCommandService.copyText(value)
            ? "\(label) copied"
            : "Copy failed"
    }

    func openOutput(_ url: URL?) -> String? {
        guard let url else {
            return "No output file found"
        }
        _ = outputCommandService.open(url)
        return nil
    }

    func copyGalleryID(
        _ result: SearchResultLink
    ) -> String {
        guard let galleryID = Self.galleryID(for: result) else {
            return "No gallery ID"
        }
        return clipboardCommandService.copyText(galleryID)
            ? "Gallery ID copied"
            : "Copy failed"
    }

    nonisolated static func browserURL(
        for result: SearchResultLink
    ) -> URL? {
        guard let url = URL(string: result.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    nonisolated static func copyTitle(
        for result: SearchResultLink
    ) -> String? {
        let title = result.title.trimmed
        return title.isEmpty ? nil : title
    }

    nonisolated static func galleryID(
        for result: SearchResultLink
    ) -> String? {
        guard let url = URL(string: result.url),
              let host = url.host?.lowercased(),
              host == "hitomi.la" ||
                host == "www.hitomi.la" else {
            return nil
        }
        return HitomiResolver.galleryID(from: url)
    }
}
