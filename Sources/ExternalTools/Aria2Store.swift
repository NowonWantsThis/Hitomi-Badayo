import Combine
import Foundation

@MainActor
final class Aria2Store: ObservableObject {
    @Published var selectedFiles: String
    @Published var seedTimeMinutes: String
    @Published var seedRatio: String
    @Published var maxDownloadLimit: String
    @Published var maxUploadLimit: String
    @Published var trackers: String
    @Published var anonymousMode: Bool
    @Published private(set) var fileEntries: [Aria2FileEntry]
    @Published private(set) var fileListSummary: String
    @Published private(set) var peerEntries: [Aria2PeerEntry]
    @Published private(set) var peerSummary: String
    @Published private(set) var runtimePausedJobIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        selectedFiles = defaults.string(
            forKey: "aria2SelectedFiles"
        ) ?? ""
        seedTimeMinutes = defaults.string(
            forKey: "aria2SeedTimeMinutes"
        ) ?? "0"
        seedRatio = defaults.string(forKey: "aria2SeedRatio") ?? ""
        maxDownloadLimit = defaults.string(
            forKey: "aria2MaxDownloadLimit"
        ) ?? ""
        maxUploadLimit = defaults.string(
            forKey: "aria2MaxUploadLimit"
        ) ?? ""
        trackers = defaults.string(forKey: "aria2Trackers") ?? ""
        anonymousMode = defaults.object(
            forKey: "aria2AnonymousMode"
        ) as? Bool ?? false
        fileEntries = []
        fileListSummary = ""
        peerEntries = []
        peerSummary = ""
        runtimePausedJobIDs = []
    }

    func setFileEntries(_ entries: [Aria2FileEntry]) {
        fileEntries = entries
    }

    func setFileListSummary(_ summary: String) {
        fileListSummary = summary
    }

    func setPeerEntries(_ entries: [Aria2PeerEntry]) {
        peerEntries = entries
    }

    func setPeerSummary(_ summary: String) {
        peerSummary = summary
    }

    func isRuntimePaused(jobID: UUID) -> Bool {
        runtimePausedJobIDs.contains(jobID)
    }

    func setRuntimePaused(_ isPaused: Bool, jobID: UUID) {
        if isPaused {
            runtimePausedJobIDs.insert(jobID)
        } else {
            runtimePausedJobIDs.remove(jobID)
        }
    }

    func clearRuntimePausedJobs() {
        runtimePausedJobIDs.removeAll()
    }
}
