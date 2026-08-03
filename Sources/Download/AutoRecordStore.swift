import Combine
import Foundation

@MainActor
final class AutoRecordStore: ObservableObject {
    @Published var isEnabled: Bool
    @Published var isPaused: Bool
    @Published var urlsText: String
    @Published var intervalMinutesString: String
    @Published private(set) var status: String
    @Published private(set) var isChecking: Bool

    init(
        isEnabled: Bool = false,
        isPaused: Bool = false,
        urlsText: String = "",
        intervalMinutesString: String = "10",
        status: String = "Automatic Recording Off",
        isChecking: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.isPaused = isPaused
        self.urlsText = urlsText
        self.intervalMinutesString = intervalMinutesString
        self.status = status
        self.isChecking = isChecking
    }

    func restore(
        isEnabled: Bool,
        isPaused: Bool,
        urlsText: String,
        intervalMinutesString: String,
        status: String
    ) {
        self.isEnabled = isEnabled
        self.isPaused = isPaused
        self.urlsText = urlsText
        self.intervalMinutesString = intervalMinutesString
        self.status = status
        isChecking = false
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setPaused(_ isPaused: Bool) {
        self.isPaused = isPaused
    }

    func setStatus(_ status: String) {
        self.status = status
    }

    func setChecking(_ isChecking: Bool) {
        self.isChecking = isChecking
    }
}
