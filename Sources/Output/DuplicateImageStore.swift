import Combine
import Foundation

@MainActor
final class DuplicateImageStore: ObservableObject {
    @Published private(set) var groups: [DuplicateImageGroup]
    @Published private(set) var summary: String
    @Published private(set) var isScanning: Bool
    @Published private(set) var selectedPath: String
    @Published private(set) var autoSelectedPath: String

    init(
        groups: [DuplicateImageGroup] = [],
        summary: String = "",
        isScanning: Bool = false,
        selectedPath: String = "",
        autoSelectedPath: String = ""
    ) {
        self.groups = groups
        self.summary = summary
        self.isScanning = isScanning
        self.selectedPath = selectedPath
        self.autoSelectedPath = autoSelectedPath
    }

    var duplicateFileCount: Int {
        groups.reduce(0) {
            $0 + max(0, $1.files.count - 1)
        }
    }

    func beginScan() {
        groups = []
        summary = "Scanning images..."
        isScanning = true
    }

    func setScanning(_ scanning: Bool) {
        isScanning = scanning
    }

    func completeScan(
        groups: [DuplicateImageGroup],
        selectedPath: String,
        autoSelectedPath: String,
        summary: String
    ) {
        self.groups = groups
        self.selectedPath = selectedPath
        self.autoSelectedPath = autoSelectedPath
        self.summary = summary
        isScanning = false
    }

    func failScan(summary: String) {
        groups = []
        selectedPath = ""
        autoSelectedPath = ""
        self.summary = summary
        isScanning = false
    }

    func clearResults() {
        groups = []
        summary = ""
        selectedPath = ""
        autoSelectedPath = ""
    }

    func updateSelection(
        selectedPath: String,
        autoSelectedPath: String,
        summary: String?
    ) {
        self.selectedPath = selectedPath
        self.autoSelectedPath = autoSelectedPath
        if let summary {
            self.summary = summary
        }
    }

    func select(path: String) {
        selectedPath = path
    }
}
