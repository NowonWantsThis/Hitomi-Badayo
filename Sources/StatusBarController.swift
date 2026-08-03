import AppKit
import Combine
import Foundation

struct StatusBarPresentationState: Equatable {
    let totalCount: Int
    let activeCount: Int
    let finishedCount: Int
    let failedCount: Int
    let isRunning: Bool
    let clipboardEnabled: Bool
    let language: AppInterfaceLanguage

    init(
        statuses: [JobStatus],
        isRunning: Bool,
        clipboardEnabled: Bool,
        language: AppInterfaceLanguage
    ) {
        totalCount = statuses.count
        activeCount = statuses.filter { $0 == .queued || $0 == .resolving || $0 == .downloading }.count
        finishedCount = statuses.filter { $0 == .finished }.count
        failedCount = statuses.filter { $0 == .failed }.count
        self.isRunning = isRunning
        self.clipboardEnabled = clipboardEnabled
        self.language = language
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let manager: DownloadManager
    private let queueStore: QueueStore
    private let settingsStore: SettingsStore
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(
        manager: DownloadManager,
        queueStore: QueueStore,
        settingsStore: SettingsStore
    ) {
        self.manager = manager
        self.queueStore = queueStore
        self.settingsStore = settingsStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Hitomi Badayo")
            button.imagePosition = .imageOnly
        }

        queueStore.$jobs
            .combineLatest(
                queueStore.$isRunning,
                settingsStore.$clipboardMonitorEnabled,
                settingsStore.$interfaceLanguage
            )
            .map { jobs, isRunning, clipboardEnabled, language in
                StatusBarPresentationState(
                    statuses: jobs.map(\.status),
                    isRunning: isRunning,
                    clipboardEnabled: clipboardEnabled,
                    language: language
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.refresh(state)
            }
            .store(in: &cancellables)
    }

    private func refresh(_ state: StatusBarPresentationState) {
        updateButton(state)
        rebuildMenu(state)
    }

    private func updateButton(_ state: StatusBarPresentationState) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: Self.statusSymbolName(
                isRunning: state.isRunning,
                clipboardEnabled: state.clipboardEnabled
            ),
            accessibilityDescription: "Hitomi Badayo"
        )
        button.title = ""
        let queueState = state.isRunning
            ? AppLocalization.text("Hitomi Badayo Running", language: state.language)
            : "Hitomi Badayo"
        let clipboardState = Self.clipboardMenuTitle(
            enabled: state.clipboardEnabled,
            language: state.language
        )
        button.toolTip = "\(queueState) - \(clipboardState)"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func rebuildMenu(_ state: StatusBarPresentationState) {
        let menu = NSMenu()

        let summary = NSMenuItem(title: summaryTitle(state), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(item("Show Hitomi Badayo", action: #selector(showApp)))

        let start = item("Start Queue", action: #selector(startQueue))
        start.isEnabled = !state.isRunning
        menu.addItem(start)

        let cancel = item("Stop Queue", action: #selector(cancelQueue))
        cancel.isEnabled = state.isRunning
        menu.addItem(cancel)

        menu.addItem(item("Remove All Completed Tasks", action: #selector(clearFinished)))
        menu.addItem(item("Open Download Folder", action: #selector(openDownloadFolder)))

        let clipboard = item(
            Self.clipboardMenuTitle(
                enabled: state.clipboardEnabled,
                language: state.language
            ),
            action: #selector(toggleClipboardMonitor),
            localize: false
        )
        clipboard.state = Self.clipboardMenuState(enabled: state.clipboardEnabled)
        menu.addItem(clipboard)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit", action: #selector(quit)))

        statusItem.menu = menu
    }

    nonisolated static func clipboardMenuTitle(
        enabled: Bool,
        language: AppInterfaceLanguage = AppLocalization.currentLanguage()
    ) -> String {
        AppLocalization.format(
            "Clipboard Monitor: %@",
            language: language,
            AppLocalization.text(enabled ? "On" : "Off", language: language)
        )
    }

    nonisolated static func clipboardMenuState(enabled: Bool) -> NSControl.StateValue {
        enabled ? .on : .off
    }

    nonisolated static func statusSymbolName(isRunning: Bool, clipboardEnabled: Bool) -> String {
        if clipboardEnabled {
            return isRunning ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        }
        return isRunning ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    private func summaryTitle(_ state: StatusBarPresentationState) -> String {
        if state.isRunning {
            return AppLocalization.format(
                "Running: %@ active, %@ finished, %@ failed",
                language: state.language,
                String(state.activeCount),
                String(state.finishedCount),
                String(state.failedCount)
            )
        }
        return AppLocalization.format(
            "Queue: %@, %@ finished, %@ failed",
            language: state.language,
            String(state.totalCount),
            String(state.finishedCount),
            String(state.failedCount)
        )
    }

    private func item(_ title: String, action: Selector, localize: Bool = true) -> NSMenuItem {
        let displayedTitle = localize
            ? AppLocalization.text(title, language: settingsStore.interfaceLanguage)
            : title
        let item = NSMenuItem(title: displayedTitle, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.isEmpty {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func startQueue() {
        manager.startQueue()
    }

    @objc private func cancelQueue() {
        manager.cancelQueue()
    }

    @objc private func clearFinished() {
        manager.clearFinished()
    }

    @objc private func openDownloadFolder() {
        NSWorkspace.shared.open(
            URL(
                fileURLWithPath: settingsStore.destinationPath,
                isDirectory: true
            )
        )
    }

    @objc private func toggleClipboardMonitor() {
        manager.setClipboardMonitorEnabled(!settingsStore.clipboardMonitorEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
