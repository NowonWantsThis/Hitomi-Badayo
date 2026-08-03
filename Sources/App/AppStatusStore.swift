import Combine
import Foundation

@MainActor
final class AppStatusStore: ObservableObject {
    static let activityLogLimit = 500

    @Published private(set) var autoRemoveHookStatus: String
    @Published private(set) var queueCompletionActionStatus: String
    @Published private(set) var sleepPreventionActive: Bool
    @Published private(set) var diskSpaceWarning: String
    @Published private(set) var persistenceWarning: String
    @Published private(set) var activityLog: [ActivityLogEntry]
    @Published private(set) var addSummary: String

    init(
        autoRemoveHookStatus: String = "Auto-remove Hook Off",
        queueCompletionActionStatus: String = "After completion: Do Nothing",
        sleepPreventionActive: Bool = false,
        diskSpaceWarning: String = "",
        persistenceWarning: String = "",
        activityLog: [ActivityLogEntry] = [],
        addSummary: String = ""
    ) {
        self.autoRemoveHookStatus = autoRemoveHookStatus
        self.queueCompletionActionStatus = queueCompletionActionStatus
        self.sleepPreventionActive = sleepPreventionActive
        self.diskSpaceWarning = diskSpaceWarning
        self.persistenceWarning = persistenceWarning
        self.activityLog = activityLog
        self.addSummary = addSummary
    }

    var storageWarningText: String {
        [diskSpaceWarning, persistenceWarning]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func setAutoRemoveHookStatus(_ status: String) {
        autoRemoveHookStatus = status
    }

    func setQueueCompletionActionStatus(_ status: String) {
        queueCompletionActionStatus = status
    }

    func setSleepPreventionActive(_ isActive: Bool) {
        sleepPreventionActive = isActive
    }

    func setDiskSpaceWarning(_ warning: String) {
        diskSpaceWarning = warning
    }

    func setPersistenceWarning(_ warning: String) {
        persistenceWarning = warning
    }

    func setSummary(_ summary: String) {
        addSummary = summary
        recordActivity(summary, category: "Status")
    }

    func recordActivity(
        _ message: String,
        category: String,
        timestamp: Date = Date()
    ) {
        let cleaned = message.trimmed
        guard !cleaned.isEmpty else { return }

        activityLog.append(
            ActivityLogEntry(
                timestamp: timestamp,
                category: category,
                message: cleaned
            )
        )
        if activityLog.count > Self.activityLogLimit {
            activityLog.removeFirst(activityLog.count - Self.activityLogLimit)
        }
    }

    func replaceActivityLog(with entries: [ActivityLogEntry]) {
        activityLog = entries
    }

    func clearActivityLog() {
        activityLog.removeAll()
    }
}
