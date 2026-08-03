import Combine
import Foundation

@MainActor
final class CookieStatusStore: ObservableObject {
    @Published private(set) var summary: String
    @Published private(set) var isClearing: Bool

    init(
        summary: String = "No cookies",
        isClearing: Bool = false
    ) {
        self.summary = summary
        self.isClearing = isClearing
    }

    func setSummary(_ summary: String) {
        self.summary = summary
    }

    func beginClearing(summary: String) {
        isClearing = true
        self.summary = summary
    }

    func completeClearing(summary: String) {
        self.summary = summary
        isClearing = false
    }
}
