import AppKit
import Combine
import Foundation

struct DockTileSnapshot: Equatable {
    var isRunning: Bool
    var activeCount: Int
    var queuedCount: Int
    var finishedCount: Int
    var failedCount: Int
    var totalJobs: Int
    var completedUnits: Int
    var totalUnits: Int
    var fraction: Double

    var percent: Int {
        Int((fraction * 100).rounded())
    }

    var badgeLabel: String? {
        return nil
    }

    var shouldShowProgress: Bool {
        totalJobs > 0 && (isRunning || activeCount > 0 || (fraction > 0 && fraction < 1))
    }

    var statusText: String {
        guard totalJobs > 0 else { return "No tasks" }
        return "\(percent)% [\(completedUnits)/\(totalUnits)] · \(activeCount) active · \(finishedCount)/\(totalJobs) finished"
    }
}

@MainActor
final class DockTileController {
    private let queueStore: QueueStore
    private var cancellables: Set<AnyCancellable> = []
    private let baseIcon: NSImage

    init(queueStore: QueueStore) {
        self.queueStore = queueStore
        self.baseIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

        queueStore.$jobs
            .combineLatest(queueStore.$isRunning)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    func refresh() {
        let snapshot = Self.snapshot(
            jobs: queueStore.jobs,
            isRunning: queueStore.isRunning
        )
        let dockTile = NSApp.dockTile
        dockTile.badgeLabel = snapshot.badgeLabel

        if snapshot.shouldShowProgress {
            let view = DockTileProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            view.icon = baseIcon
            view.snapshot = snapshot
            dockTile.contentView = view
        } else {
            dockTile.contentView = nil
        }
        dockTile.display()
    }

    nonisolated static func snapshot(jobs: [DownloadJob], isRunning: Bool) -> DockTileSnapshot {
        let queuedCount = jobs.filter { $0.status == .queued }.count
        let finishedCount = jobs.filter { $0.status == .finished }.count
        let failedCount = jobs.filter { $0.status == .failed }.count
        let progress = QueueProgressPresentationService.snapshot(jobs: jobs)
        return DockTileSnapshot(
            isRunning: isRunning,
            activeCount: progress.activeJobs.count,
            queuedCount: queuedCount,
            finishedCount: finishedCount,
            failedCount: failedCount,
            totalJobs: jobs.count,
            completedUnits: progress.completedUnits,
            totalUnits: progress.totalUnits,
            fraction: progress.fraction
        )
    }
}

private final class DockTileProgressView: NSView {
    var icon: NSImage?
    var snapshot = DockTileSnapshot(
        isRunning: false,
        activeCount: 0,
        queuedCount: 0,
        finishedCount: 0,
        failedCount: 0,
        totalJobs: 0,
        completedUnits: 0,
        totalUnits: 0,
        fraction: 0
    )

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = bounds.insetBy(dx: 7, dy: 7)
        icon?.draw(in: iconRect)

        let barRect = NSRect(
            x: bounds.minX + bounds.width * 0.14,
            y: bounds.minY + bounds.height * 0.12,
            width: bounds.width * 0.72,
            height: max(8, bounds.height * 0.085)
        )
        let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barRect.height / 2, yRadius: barRect.height / 2)
        NSColor.black.withAlphaComponent(0.45).setFill()
        trackPath.fill()

        if snapshot.fraction > 0 {
            let fillRect = NSRect(
                x: barRect.minX,
                y: barRect.minY,
                width: max(barRect.height, barRect.width * snapshot.fraction),
                height: barRect.height
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: fillRect.height / 2, yRadius: fillRect.height / 2)
            NSColor.systemBlue.setFill()
            fillPath.fill()
        }

        drawFailureIndicatorIfNeeded()
    }

    private func drawFailureIndicatorIfNeeded() {
        guard snapshot.failedCount > 0 else { return }
        let diameter = bounds.width * 0.22
        let rect = NSRect(
            x: bounds.maxX - diameter - bounds.width * 0.11,
            y: bounds.maxY - diameter - bounds.height * 0.12,
            width: diameter,
            height: diameter
        )
        let dot = NSBezierPath(ovalIn: rect)
        NSColor.systemRed.setFill()
        dot.fill()
    }
}
