import Foundation

struct AppShortcutCommandActions {
    var showHelp: () -> Void
    var openSettings: () -> Void
    var openShortcutSettings: () -> Void
    var pasteURLs: () -> Void
    var startQueue: () -> Void
    var openProgress: () -> Void
    var moveSelectedJobsUp: () -> Void
    var moveSelectedJobsDown: () -> Void
    var showStatistics: () -> Void
    var showActivityLog: () -> Void
    var showHistory: () -> Void
    var showDirectories: () -> Void
    var showMetadataFinder: () -> Void
    var showMetadataAnalysis: () -> Void
    var showSearcher: () -> Void
    var openBrowser: () -> Void
    var openTextViewer: () -> Void
    var openOutputPreview: () -> Void
    var editStatusColors: () -> Void
    var openFontSettings: () -> Void
    var toggleFloatingMonitor: () -> Void
    var openDuplicateImageFinder: () -> Void
    var openClipboardViewer: () -> Void
    var openDuplicateImageFolder: () -> Void
    var showArtistRecommendations: () -> Void
    var openHitomiTaster: () -> Void
}

struct AppShortcutDraftRecording:
    Equatable
{
    var shortcut: AppShortcut?
    var message: String
}

@MainActor
final class AppShortcutCommandService {
    func draftRecording(
        for shortcut: AppShortcut?
    ) -> AppShortcutDraftRecording {
        guard let shortcut else {
            return AppShortcutDraftRecording(
                shortcut: nil,
                message: "Unsupported key"
            )
        }
        return AppShortcutDraftRecording(
            shortcut: shortcut,
            message:
                "\(shortcut.displayText) recorded"
        )
    }

    func perform(
        _ command: AppShortcutCommand,
        actions: AppShortcutCommandActions
    ) {
        switch command {
        case .help:
            actions.showHelp()
        case .settings:
            actions.openSettings()
        case .shortcuts:
            actions.openShortcutSettings()
        case .pasteURLs:
            actions.pasteURLs()
        case .startQueue:
            actions.startQueue()
        case .progressWindow:
            actions.openProgress()
        case .moveSelectedJobsUp:
            actions.moveSelectedJobsUp()
        case .moveSelectedJobsDown:
            actions.moveSelectedJobsDown()
        case .statistics:
            actions.showStatistics()
        case .activityLog:
            actions.showActivityLog()
        case .historyWindow:
            actions.showHistory()
        case .directories:
            actions.showDirectories()
        case .metadataFinder:
            actions.showMetadataFinder()
        case .metadataAnalysis:
            actions.showMetadataAnalysis()
        case .searcher:
            actions.showSearcher()
        case .browserWindow:
            actions.openBrowser()
        case .textViewer:
            actions.openTextViewer()
        case .outputPreview:
            actions.openOutputPreview()
        case .statusColors:
            actions.editStatusColors()
        case .fontSettings:
            actions.openFontSettings()
        case .floatingMonitor:
            actions.toggleFloatingMonitor()
        case .duplicateImageFinder:
            actions.openDuplicateImageFinder()
        case .clipboardViewer:
            actions.openClipboardViewer()
        case .openDuplicateImageFolder:
            actions.openDuplicateImageFolder()
        case .artistRecommendations:
            actions.showArtistRecommendations()
        case .hitomiTaster:
            actions.openHitomiTaster()
        }
    }
}
