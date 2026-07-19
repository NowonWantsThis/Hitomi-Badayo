import AppKit
import Combine
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let manager: DownloadManager
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(manager: DownloadManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Hitomi Badayo")
            button.imagePosition = .imageLeading
        }

        manager.$jobs
            .combineLatest(manager.$isRunning, manager.$clipboardMonitorEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        manager.$interfaceLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        updateButton()
        rebuildMenu()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let activeCount = manager.jobs.filter { $0.status == .queued || $0.status == .resolving || $0.status == .downloading }.count
        button.image = NSImage(
            systemSymbolName: Self.statusSymbolName(
                isRunning: manager.isRunning,
                clipboardEnabled: manager.clipboardMonitorEnabled
            ),
            accessibilityDescription: "Hitomi Badayo"
        )
        button.title = Self.statusButtonTitle(activeCount: activeCount, clipboardEnabled: manager.clipboardMonitorEnabled)
        let queueState = manager.isRunning
            ? AppLocalization.text("Hitomi Badayo 실행 중", language: manager.interfaceLanguage)
            : "Hitomi Badayo"
        let clipboardState = Self.clipboardMenuTitle(
            enabled: manager.clipboardMonitorEnabled,
            language: manager.interfaceLanguage
        )
        button.toolTip = "\(queueState) - \(clipboardState)"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let summary = NSMenuItem(title: summaryTitle, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(item("Hitomi Badayo 보기", action: #selector(showApp)))

        let start = item("대기열 시작", action: #selector(startQueue))
        start.isEnabled = !manager.isRunning
        menu.addItem(start)

        let cancel = item("대기열 중지", action: #selector(cancelQueue))
        cancel.isEnabled = manager.isRunning
        menu.addItem(cancel)

        menu.addItem(item("완료된 작업 모두 제거", action: #selector(clearFinished)))
        menu.addItem(item("다운로드 폴더 열기", action: #selector(openDownloadFolder)))

        let clipboard = item(
            Self.clipboardMenuTitle(
                enabled: manager.clipboardMonitorEnabled,
                language: manager.interfaceLanguage
            ),
            action: #selector(toggleClipboardMonitor),
            localize: false
        )
        clipboard.state = Self.clipboardMenuState(enabled: manager.clipboardMonitorEnabled)
        menu.addItem(clipboard)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("종료", action: #selector(quit)))

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

    nonisolated static func statusButtonTitle(activeCount: Int, clipboardEnabled: Bool) -> String {
        let count = max(0, activeCount)
        switch (count, clipboardEnabled) {
        case (0, false):
            return ""
        case (0, true):
            return " Clip"
        case (_, false):
            return " \(count)"
        case (_, true):
            return " \(count) Clip"
        }
    }

    nonisolated static func statusSymbolName(isRunning: Bool, clipboardEnabled: Bool) -> String {
        if clipboardEnabled {
            return isRunning ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        }
        return isRunning ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    private var summaryTitle: String {
        let total = manager.jobs.count
        let active = manager.jobs.filter { $0.status == .queued || $0.status == .resolving || $0.status == .downloading }.count
        let finished = manager.jobs.filter { $0.status == .finished }.count
        let failed = manager.jobs.filter { $0.status == .failed }.count

        if manager.isRunning {
            return AppLocalization.format(
                "Running: %@ active, %@ finished, %@ failed",
                language: manager.interfaceLanguage,
                String(active),
                String(finished),
                String(failed)
            )
        }
        return AppLocalization.format(
            "Queue: %@, %@ finished, %@ failed",
            language: manager.interfaceLanguage,
            String(total),
            String(finished),
            String(failed)
        )
    }

    private func item(_ title: String, action: Selector, localize: Bool = true) -> NSMenuItem {
        let displayedTitle = localize
            ? AppLocalization.text(title, language: manager.interfaceLanguage)
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
        NSWorkspace.shared.open(URL(fileURLWithPath: manager.destinationPath, isDirectory: true))
    }

    @objc private func toggleClipboardMonitor() {
        manager.setClipboardMonitorEnabled(!manager.clipboardMonitorEnabled)
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
