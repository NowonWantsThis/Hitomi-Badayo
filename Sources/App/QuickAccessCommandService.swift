import Foundation

struct QuickAccessCommandContext: Equatable {
    var hasQueueContent: Bool
    var usesManualQueueSort: Bool
    var isQueueRunning: Bool
    var canSelectRandomVisibleJob: Bool
    var mainWindowAlwaysOnTop: Bool
    var appearanceMode: AppAppearanceMode
}

struct QuickAccessCommandActions {
    var exportTasks: () -> Void
    var createGroup: () -> Void
    var toggleQueueView: () -> Void
    var selectRandomJob: () -> Void
    var setMainWindowAlwaysOnTop: (Bool) -> Void
    var setAppearanceMode: (AppAppearanceMode) -> Void
    var importCookies: () -> Void
    var openBrowser: () -> Void
}

@MainActor
final class QuickAccessCommandService {
    func canPerform(
        _ command: QuickAccessCommand,
        context: QuickAccessCommandContext
    ) -> Bool {
        switch command {
        case .save:
            return context.hasQueueContent
        case .group:
            return context.usesManualQueueSort &&
                !context.isQueueRunning
        case .random:
            return context.canSelectRandomVisibleJob
        case .view, .top, .darkMode, .loadCookie, .webBrowser:
            return true
        }
    }

    func isActive(
        _ command: QuickAccessCommand,
        context: QuickAccessCommandContext
    ) -> Bool {
        switch command {
        case .top:
            return context.mainWindowAlwaysOnTop
        case .darkMode:
            return context.appearanceMode == .dark
        default:
            return false
        }
    }

    @discardableResult
    func perform(
        _ command: QuickAccessCommand,
        context: QuickAccessCommandContext,
        actions: QuickAccessCommandActions
    ) -> Bool {
        guard canPerform(command, context: context) else {
            return false
        }

        switch command {
        case .save:
            actions.exportTasks()
        case .group:
            actions.createGroup()
        case .view:
            actions.toggleQueueView()
        case .random:
            actions.selectRandomJob()
        case .top:
            actions.setMainWindowAlwaysOnTop(
                !context.mainWindowAlwaysOnTop
            )
        case .darkMode:
            actions.setAppearanceMode(
                context.appearanceMode == .dark ? .light : .dark
            )
        case .loadCookie:
            actions.importCookies()
        case .webBrowser:
            actions.openBrowser()
        }
        return true
    }
}
