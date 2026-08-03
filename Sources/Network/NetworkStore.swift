import Combine
import Foundation

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var dpiBypassSnapshot: BrowserDPIBypassSnapshot
    @Published private(set) var publicIPStatus: String
    @Published private(set) var isRefreshingPublicIP: Bool
    @Published private(set) var httpAPIStatus: String
    @Published private(set) var browserExtensionStatus: String

    init(
        dpiBypassSnapshot: BrowserDPIBypassSnapshot = BrowserDPIBypassSnapshot(
            phase: .off,
            endpoint: BrowserDPIProxyEndpoint()
        ),
        publicIPStatus: String = "Public IP Not Checked",
        isRefreshingPublicIP: Bool = false,
        httpAPIStatus: String = "HTTP API Off",
        browserExtensionStatus: String = "Browser extension off"
    ) {
        self.dpiBypassSnapshot = dpiBypassSnapshot
        self.publicIPStatus = publicIPStatus
        self.isRefreshingPublicIP = isRefreshingPublicIP
        self.httpAPIStatus = httpAPIStatus
        self.browserExtensionStatus = browserExtensionStatus
    }

    func setDPIBypassSnapshot(_ snapshot: BrowserDPIBypassSnapshot) {
        dpiBypassSnapshot = snapshot
    }

    func setPublicIPStatus(_ status: String) {
        publicIPStatus = status
    }

    func setRefreshingPublicIP(_ isRefreshing: Bool) {
        isRefreshingPublicIP = isRefreshing
    }

    func setHTTPAPIStatus(_ status: String) {
        httpAPIStatus = status
    }

    func setBrowserExtensionStatus(_ status: String) {
        browserExtensionStatus = status
    }
}
