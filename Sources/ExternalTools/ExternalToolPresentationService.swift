import Foundation

@MainActor
enum ExternalToolPresentationService {
    static func statuses(
        store: ExternalToolStore
    ) -> [ExternalToolStatus] {
        ExternalToolStatusService.statuses(
            ytdlpPath: store.ytdlpPath,
            denoPath: store.denoPath,
            ffmpegPath: store.ffmpegPath,
            aria2Path: store.aria2Path
        )
    }

    static func availabilitySummary(
        store: ExternalToolStore,
        language: AppInterfaceLanguage
    ) -> String {
        statuses(store: store)
            .map {
                let state = AppLocalization.text(
                    $0.isAvailable ? "Ready" : "Missing",
                    language: language
                )
                return "\($0.name) \(state)"
            }
            .joined(separator: " · ")
    }
}
