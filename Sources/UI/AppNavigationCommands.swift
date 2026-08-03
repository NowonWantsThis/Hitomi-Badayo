import SwiftUI

struct AppNavigationCommands {
    private let service: AppCommandService?

    init(service: AppCommandService? = nil) {
        self.service = service
    }

    @MainActor
    func openSettings(_ category: SettingsWindowCategory = .general) {
        service?.openSettingsWindow(category: category)
    }

    @MainActor
    func closeSettings() {
        service?.closeSettingsWindow()
    }

    @MainActor
    func openShortcuts() {
        service?.openShortcutSettings()
    }

    @MainActor
    func closeShortcuts() {
        service?.closeShortcutSettings()
    }

    @MainActor
    func setFloatingMonitorVisible(_ visible: Bool) {
        service?.setFloatingMonitorVisible(visible)
    }

    @MainActor
    func openDuplicateImageFinder() {
        service?.openDuplicateImageFinder()
    }

    @MainActor
    func closeDuplicateImageFinder() {
        service?.closeDuplicateImageFinder()
    }

    @MainActor
    func openClipboardViewer() {
        service?.openClipboardViewer()
    }

    @MainActor
    func closeClipboardViewer() {
        service?.closeClipboardViewer()
    }

    @MainActor
    func openBrowser() {
        service?.openBrowserWindow()
    }

    @MainActor
    func closeBrowser() {
        service?.closeBrowserWindow()
    }

    @MainActor
    func openTextViewer() {
        service?.openTextViewer()
    }

    @MainActor
    func closeTextViewer() {
        service?.closeTextViewer()
    }

    @MainActor
    func openProgress() {
        service?.openProgressWindow()
    }

    @MainActor
    func closeProgress() {
        service?.closeProgressWindow()
    }

    @MainActor
    func open(_ window: AppAuxiliaryWindow) {
        service?.openAuxiliaryWindow(window)
    }

    @MainActor
    func close(_ window: AppAuxiliaryWindow) {
        service?.closeAuxiliaryWindow(window)
    }
}

private struct AppNavigationCommandsKey: EnvironmentKey {
    static let defaultValue = AppNavigationCommands()
}

extension EnvironmentValues {
    var appNavigationCommands: AppNavigationCommands {
        get { self[AppNavigationCommandsKey.self] }
        set { self[AppNavigationCommandsKey.self] = newValue }
    }
}
