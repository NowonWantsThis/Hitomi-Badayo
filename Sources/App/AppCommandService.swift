import Foundation

enum AppAuxiliaryWindow: CaseIterable {
    case quickAccessCustomization
    case statistics
    case activityLog
    case directories
    case history
    case searcher
    case metadataFinder
    case metadataAnalysis
    case about
    case help
    case artistRecommendations
    case hitomiTaster
    case statusColorPicker
    case fontSettings
}

@MainActor
final class AppCommandService {
    let presentation: AppPresentationStore

    private let defaults: UserDefaults

    init(
        presentation: AppPresentationStore,
        defaults: UserDefaults = .standard
    ) {
        self.presentation = presentation
        self.defaults = defaults
    }

    func openSettingsWindow(category: SettingsWindowCategory) {
        presentation.settingsWindow.prepare(category: category)
        presentation.showingSettingsWindow = true
    }

    func closeSettingsWindow() {
        presentation.showingSettingsWindow = false
    }

    func openShortcutSettings() {
        presentation.showingShortcutSettings = true
    }

    func closeShortcutSettings() {
        presentation.showingShortcutSettings = false
    }

    func setFloatingMonitorVisible(_ visible: Bool) {
        presentation.showingFloatingMonitor = visible
        defaults.set(visible, forKey: "showingFloatingMonitor")
    }

    func openDuplicateImageFinder() {
        presentation.showingDuplicateImageFinder = true
    }

    func closeDuplicateImageFinder() {
        presentation.showingDuplicateImageFinder = false
    }

    func openClipboardViewer() {
        presentation.showingClipboardViewer = true
    }

    func closeClipboardViewer() {
        presentation.showingClipboardViewer = false
    }

    func openBrowserWindow() {
        presentation.showingBrowserWindow = true
    }

    func closeBrowserWindow() {
        presentation.showingBrowserWindow = false
    }

    func openTextViewer() {
        presentation.showingTextViewer = true
    }

    func closeTextViewer() {
        presentation.showingTextViewer = false
    }

    func openProgressWindow() {
        presentation.showingProgressWindow = true
    }

    func closeProgressWindow() {
        presentation.showingProgressWindow = false
    }

    func openAuxiliaryWindow(_ window: AppAuxiliaryWindow) {
        setAuxiliaryWindow(window, visible: true)
    }

    func closeAuxiliaryWindow(_ window: AppAuxiliaryWindow) {
        setAuxiliaryWindow(window, visible: false)
    }

    private func setAuxiliaryWindow(
        _ window: AppAuxiliaryWindow,
        visible: Bool
    ) {
        switch window {
        case .quickAccessCustomization:
            presentation.showingQuickAccessCustomization = visible
        case .statistics:
            presentation.showingStatistics = visible
        case .activityLog:
            presentation.showingActivityLog = visible
        case .directories:
            presentation.showingDirectories = visible
        case .history:
            presentation.showingHistoryWindow = visible
        case .searcher:
            presentation.showingSearcher = visible
        case .metadataFinder:
            presentation.showingMetadataFinder = visible
        case .metadataAnalysis:
            presentation.showingMetadataAnalysis = visible
        case .about:
            presentation.showingAbout = visible
        case .help:
            presentation.showingHelp = visible
        case .artistRecommendations:
            presentation.showingArtistRecommendations = visible
        case .hitomiTaster:
            presentation.showingHitomiTaster = visible
        case .statusColorPicker:
            presentation.showingStatusColorPicker = visible
        case .fontSettings:
            presentation.showingFontSettings = visible
        }
    }
}
