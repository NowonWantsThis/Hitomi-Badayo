import AppKit
import CFNetwork
import Darwin
import Foundation

struct BrowserDPIProxyEndpoint: Codable, Equatable, Sendable {
    static let defaultPort: UInt16 = 8_080

    var host: String = "127.0.0.1"
    var port: UInt16 = defaultPort

    var displayValue: String {
        "\(host):\(port)"
    }
}

enum BrowserDPIBypassPhase: Equatable, Sendable {
    case off
    case starting
    case detectingNetwork
    case configuringSystemProxy
    case waitingForSystemProxy
    case partiallyConfigured
    case active
    case conflictingSystemProxy
    case restoringSystemProxy
    case restoreRequired
    case waitingForProxyRemoval
    case failed

    var localizationKey: String {
        switch self {
        case .off: return "DPI Bypass Off"
        case .starting: return "Starting DPI Bypass"
        case .detectingNetwork: return "Detecting Active Network"
        case .configuringSystemProxy: return "Configuring macOS Proxy"
        case .waitingForSystemProxy: return "Waiting for macOS Proxy Settings"
        case .partiallyConfigured: return "Configure Both Web Proxies"
        case .active: return "DPI Bypass Active"
        case .conflictingSystemProxy: return "Different System Proxy Detected"
        case .restoringSystemProxy: return "Restoring Network Settings"
        case .restoreRequired: return "Network Settings Must Be Restored"
        case .waitingForProxyRemoval: return "Waiting for macOS Proxy to Be Disabled"
        case .failed: return "DPI Bypass Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "shield.slash"
        case .starting, .detectingNetwork, .configuringSystemProxy, .restoringSystemProxy:
            return "hourglass"
        case .waitingForSystemProxy, .partiallyConfigured, .waitingForProxyRemoval:
            return "gearshape.2"
        case .active: return "checkmark.shield.fill"
        case .conflictingSystemProxy, .restoreRequired, .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .detectingNetwork, .configuringSystemProxy, .restoringSystemProxy:
            return true
        default:
            return false
        }
    }
}

enum SystemBrowserProxyState: Equatable, Sendable {
    case inactive
    case partial
    case active
    case conflicting
}

struct BrowserDPIBypassSnapshot: Equatable, Sendable {
    var phase: BrowserDPIBypassPhase
    var endpoint: BrowserDPIProxyEndpoint
    var diagnostic: String = ""
    var networkService: String = ""
    var hasRestorableProxySettings = false
}

enum SystemBrowserProxyDetector {
    static func currentState(for endpoint: BrowserDPIProxyEndpoint) -> SystemBrowserProxyState {
        guard let settings = currentSettings else {
            return .inactive
        }
        return state(in: settings, endpoint: endpoint)
    }

    static func currentSettingsUse(_ endpoint: BrowserDPIProxyEndpoint) -> Bool {
        guard let settings = currentSettings else { return false }
        return uses(endpoint, in: settings)
    }

    static func state(
        in settings: [String: Any],
        endpoint: BrowserDPIProxyEndpoint
    ) -> SystemBrowserProxyState {
        let httpEnabled = boolValue(settings["HTTPEnable"])
        let httpsEnabled = boolValue(settings["HTTPSEnable"])
        let pacEnabled = boolValue(settings["ProxyAutoConfigEnable"])
        let socksEnabled = boolValue(settings["SOCKSEnable"])

        let httpMatches = httpEnabled && proxyMatches(
            host: settings["HTTPProxy"],
            port: settings["HTTPPort"],
            endpoint: endpoint
        )
        let httpsMatches = httpsEnabled && proxyMatches(
            host: settings["HTTPSProxy"],
            port: settings["HTTPSPort"],
            endpoint: endpoint
        )

        let hasDifferentHTTPProxy = httpEnabled && !httpMatches
        let hasDifferentHTTPSProxy = httpsEnabled && !httpsMatches
        if pacEnabled || socksEnabled || hasDifferentHTTPProxy || hasDifferentHTTPSProxy {
            return .conflicting
        }
        if httpMatches && httpsMatches {
            return .active
        }
        if httpMatches || httpsMatches {
            return .partial
        }
        return .inactive
    }

    static func uses(
        _ endpoint: BrowserDPIProxyEndpoint,
        in settings: [String: Any]
    ) -> Bool {
        let httpMatches = boolValue(settings["HTTPEnable"]) && proxyMatches(
            host: settings["HTTPProxy"],
            port: settings["HTTPPort"],
            endpoint: endpoint
        )
        let httpsMatches = boolValue(settings["HTTPSEnable"]) && proxyMatches(
            host: settings["HTTPSProxy"],
            port: settings["HTTPSPort"],
            endpoint: endpoint
        )
        return httpMatches || httpsMatches
    }

    private static var currentSettings: [String: Any]? {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
    }

    private static func proxyMatches(
        host: Any?,
        port: Any?,
        endpoint: BrowserDPIProxyEndpoint
    ) -> Bool {
        guard let host = host as? String,
              let port = intValue(port) else {
            return false
        }
        let normalizedHost = host.trimmed.lowercased()
        let expectedHost = endpoint.host.lowercased()
        let hostMatches = normalizedHost == expectedHost ||
            (Self.loopbackHosts.contains(normalizedHost) && Self.loopbackHosts.contains(expectedHost))
        return hostMatches && port == Int(endpoint.port)
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        if let value = value as? String {
            return ["1", "true", "yes", "on"].contains(value.trimmed.lowercased())
        }
        return false
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value.trimmed) }
        return nil
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
}

@MainActor
final class BrowserDPIBypassService {
    typealias UpdateHandler = @MainActor (BrowserDPIBypassSnapshot) -> Void

    nonisolated private static let portKey = "browserDPIBypassPort"
    nonisolated private static let proxyBackupKey = "browserDPIProxyBackup"
    nonisolated private static let defaultFallbackPorts = Array(UInt16(18_080)...UInt16(18_179))

    private let defaults: UserDefaults
    private let environment: [String: String]
    private let fileManager: FileManager
    private let proxyAutomation: SystemBrowserProxyAutomation
    private let automaticProxyConfigurationEnabled: Bool
    private var requestedMode: DPIBypassMode = .off
    private var process: Process?
    private var logHandle: FileHandle?
    private var readinessTask: Task<Void, Never>?
    private var proxyAutomationTask: Task<Void, Never>?
    private var monitorTimer: Timer?
    private var intentionalStop = false
    private var stopAfterProxyRemoval = false
    private var restoreSystemProxyForAppOnlyTransition = false
    private var terminalPhaseAfterStop: (BrowserDPIBypassPhase, String)?
    private var proxyBackup: BrowserDPIProxyBackup?
    private(set) var snapshot: BrowserDPIBypassSnapshot
    var onUpdate: UpdateHandler?

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        commandRunner: any BrowserDPICommandRunning = BrowserDPIProcessCommandRunner()
    ) {
        self.defaults = defaults
        self.environment = environment
        self.fileManager = fileManager
        proxyAutomation = SystemBrowserProxyAutomation(runner: commandRunner)
        automaticProxyConfigurationEnabled =
            environment["HITOMI_NATIVE_SKIP_SYSTEM_PROXY_AUTOMATION"] != "1"
        let port = Self.configuredPort(defaults: defaults, environment: environment)
        let loadedBackup = Self.loadProxyBackup(defaults: defaults)
        let restoreRequired = loadedBackup.map {
            SystemBrowserProxyDetector.currentSettingsUse($0.endpoint)
        } ?? false
        let backup = restoreRequired ? loadedBackup : nil
        if loadedBackup != nil, !restoreRequired {
            defaults.removeObject(forKey: Self.proxyBackupKey)
        }
        proxyBackup = backup
        let endpoint = backup?.endpoint ?? BrowserDPIProxyEndpoint(port: port)
        snapshot = BrowserDPIBypassSnapshot(
            phase: restoreRequired ? .restoreRequired : .off,
            endpoint: endpoint,
            networkService: backup?.networkService ?? "",
            hasRestorableProxySettings: backup != nil
        )
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    var requiresProxyRestorationBeforeTermination: Bool {
        snapshot.hasRestorableProxySettings ||
            appOnlyTransitionProxyIsActive ||
            (requestedMode == .appAndBrowsers &&
                SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint))
    }

    var logURL: URL {
        AppPaths.applicationSupportDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("spoofdpi.log")
    }

    func setMode(_ mode: DPIBypassMode, openSystemSettings: Bool) {
        if mode == .off {
            requestStop(openSystemSettings: openSystemSettings)
        } else {
            start(mode: mode, openSystemSettings: openSystemSettings)
        }
    }

    func start(mode: DPIBypassMode, openSystemSettings: Bool) {
        guard mode.usesLocalProxy else {
            requestStop(openSystemSettings: openSystemSettings)
            return
        }
        let previousMode = requestedMode
        requestedMode = mode
        if previousMode == .appAndBrowsers,
           mode == .appOnly,
           SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint) {
            restoreSystemProxyForAppOnlyTransition = true
        } else if mode == .appAndBrowsers {
            restoreSystemProxyForAppOnlyTransition = false
        }

        guard process?.isRunning != true else {
            stopAfterProxyRemoval = false
            activateRequestedMode(openSystemSettings: openSystemSettings)
            return
        }

        readinessTask?.cancel()
        proxyAutomationTask?.cancel()
        proxyAutomationTask = nil
        stopMonitor()
        intentionalStop = false
        stopAfterProxyRemoval = false
        terminalPhaseAfterStop = nil
        publish(phase: .starting, diagnostic: "")

        guard let executable = executableURL else {
            publish(phase: .failed, diagnostic: "Bundled SpoofDPI executable is missing.")
            return
        }
        if let proxyBackup,
           SystemBrowserProxyDetector.currentSettingsUse(proxyBackup.endpoint),
           Self.canConnect(port: proxyBackup.endpoint.port) {
            snapshot.endpoint = proxyBackup.endpoint
            publish(
                phase: .active,
                diagnostic: "",
                networkService: proxyBackup.networkService
            )
            activateRequestedMode(openSystemSettings: openSystemSettings)
            return
        }
        guard let port = selectAvailablePort() else {
            let phase: BrowserDPIBypassPhase = proxyBackup == nil ? .failed : .restoreRequired
            publish(phase: phase, diagnostic: "No local proxy port is available.")
            return
        }

        let endpoint = BrowserDPIProxyEndpoint(port: port)
        snapshot.endpoint = endpoint
        if environment["HITOMI_NATIVE_SPOOFDPI_PORT"] == nil {
            defaults.set(Int(port), forKey: Self.portKey)
        }

        do {
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            fileManager.createFile(atPath: logURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.truncate(atOffset: 0)
            let process = Process()
            process.executableURL = executable
            process.arguments = Self.arguments(for: endpoint)
            process.standardOutput = handle
            process.standardError = handle
            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.processDidTerminate(terminatedProcess)
                    }
                }
            }
            try process.run()
            self.process = process
            logHandle = handle
        } catch {
            closeLogHandle()
            publish(phase: .failed, diagnostic: "Could not start SpoofDPI.")
            return
        }

        readinessTask = Task { [weak self] in
            guard let self else { return }
            let ready = await Self.waitUntilListening(on: endpoint.port)
            guard !Task.isCancelled else { return }
            readinessTask = nil
            if ready, process?.isRunning == true {
                activateRequestedMode(openSystemSettings: openSystemSettings)
            } else if process?.isRunning == true {
                terminateImmediately(
                    finalPhase: .failed,
                    diagnostic: "SpoofDPI did not open its local proxy port."
                )
            }
        }
    }

    func requestStop(openSystemSettings: Bool) {
        let previousMode = requestedMode
        requestedMode = .off
        readinessTask?.cancel()
        readinessTask = nil
        proxyAutomationTask?.cancel()
        proxyAutomationTask = nil
        stopMonitor()

        let needsRestoration = snapshot.hasRestorableProxySettings ||
            appOnlyTransitionProxyIsActive ||
            (previousMode == .appAndBrowsers &&
                SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint))
        if automaticProxyConfigurationEnabled, needsRestoration {
            beginAutomaticProxyRestoration(
                openSystemSettingsOnFailure: openSystemSettings,
                stopAfterRestoring: true
            )
            return
        }

        guard process?.isRunning == true else {
            publish(phase: .off, diagnostic: "")
            return
        }

        if SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint) {
            stopAfterProxyRemoval = true
            publish(phase: .waitingForProxyRemoval, diagnostic: "")
            startMonitor()
            if openSystemSettings {
                _ = openSystemProxySettings()
            }
            return
        }

        terminateImmediately()
    }

    func refreshSystemProxyState() {
        guard !snapshot.phase.isBusy else {
            return
        }
        guard process?.isRunning == true else {
            if snapshot.phase != .failed, !snapshot.hasRestorableProxySettings {
                publish(phase: .off, diagnostic: "")
            }
            return
        }

        if requestedMode == .appOnly {
            if restoreSystemProxyForAppOnlyTransition,
               !SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint) {
                restoreSystemProxyForAppOnlyTransition = false
            }
            if snapshot.hasRestorableProxySettings ||
                appOnlyTransitionProxyIsActive {
                publish(
                    phase: .restoreRequired,
                    diagnostic: "Restore the macOS proxy settings to finish switching to App Only"
                )
            } else {
                publish(phase: .active, diagnostic: "", networkService: "")
            }
            return
        }

        let systemState = SystemBrowserProxyDetector.currentState(for: snapshot.endpoint)
        if stopAfterProxyRemoval {
            if SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint) {
                publish(phase: .waitingForProxyRemoval, diagnostic: "")
            } else {
                terminateImmediately()
            }
            return
        }

        switch systemState {
        case .inactive:
            publish(phase: .waitingForSystemProxy, diagnostic: "")
        case .partial:
            publish(phase: .partiallyConfigured, diagnostic: "")
        case .active:
            publish(phase: .active, diagnostic: "")
        case .conflicting:
            publish(phase: .conflictingSystemProxy, diagnostic: "")
        }
    }

    func restoreSystemProxySettings() {
        requestedMode = .off
        proxyAutomationTask?.cancel()
        proxyAutomationTask = nil
        beginAutomaticProxyRestoration(
            openSystemSettingsOnFailure: true,
            stopAfterRestoring: true
        )
    }

    func restoreBeforeTermination() async -> Bool {
        requestedMode = .off
        readinessTask?.cancel()
        readinessTask = nil
        proxyAutomationTask?.cancel()
        proxyAutomationTask = nil
        stopMonitor()

        guard requiresProxyRestorationBeforeTermination else {
            terminateImmediately()
            await waitForLocalProxyTermination()
            return true
        }
        let restored = await restoreSystemProxyAutomatically(
            openSystemSettingsOnFailure: true,
            stopAfterRestoring: true
        )
        if restored {
            await waitForLocalProxyTermination()
        }
        return restored
    }

    private func beginAutomaticProxyConfiguration(
        openSystemSettingsOnFailure: Bool
    ) {
        guard proxyAutomationTask == nil else { return }
        stopMonitor()
        proxyAutomationTask = Task { [weak self] in
            guard let self else { return }
            await configureSystemProxyAutomatically(
                openSystemSettingsOnFailure: openSystemSettingsOnFailure
            )
            proxyAutomationTask = nil
        }
    }

    private func configureSystemProxyAutomatically(
        openSystemSettingsOnFailure: Bool
    ) async {
        guard process?.isRunning == true,
              requestedMode == .appAndBrowsers else {
            return
        }

        let currentState = SystemBrowserProxyDetector.currentState(for: snapshot.endpoint)
        if currentState == .active {
            startMonitor()
            publish(phase: .active, diagnostic: "")
            return
        }
        if currentState == .conflicting {
            if openSystemSettingsOnFailure {
                _ = openSystemProxySettings()
            }
            terminateImmediately(
                finalPhase: .conflictingSystemProxy,
                diagnostic: BrowserDPIProxyAutomationError
                    .existingProxyConfiguration
                    .diagnosticKey
            )
            return
        }

        publish(phase: .detectingNetwork, diagnostic: "")
        do {
            let backup = try await proxyAutomation.makeBackup(for: snapshot.endpoint)
            guard !Task.isCancelled else { return }
            saveProxyBackup(backup)
            publish(
                phase: .configuringSystemProxy,
                diagnostic: "",
                networkService: backup.networkService
            )
            try await proxyAutomation.apply(backup)
            guard !Task.isCancelled else { return }

            if await waitForSystemProxy(active: true) {
                startMonitor()
                publish(
                    phase: .active,
                    diagnostic: "",
                    networkService: backup.networkService
                )
            } else {
                publish(
                    phase: .restoreRequired,
                    diagnostic: "macOS did not activate the automatic proxy settings.",
                    networkService: backup.networkService
                )
            }
        } catch {
            let automationError = error as? BrowserDPIProxyAutomationError ?? .commandFailed
            if automationError == .authorizationCancelled {
                clearProxyBackup()
                terminateImmediately(
                    finalPhase: .failed,
                    diagnostic: automationError.diagnosticKey
                )
            } else if proxyBackup != nil {
                publish(
                    phase: .restoreRequired,
                    diagnostic: automationError.diagnosticKey
                )
            } else {
                if openSystemSettingsOnFailure,
                   automationError == .existingProxyConfiguration ||
                    automationError == .authenticatedProxyConfiguration {
                    _ = openSystemProxySettings()
                }
                terminateImmediately(
                    finalPhase: automationError == .existingProxyConfiguration
                        ? .conflictingSystemProxy
                        : .failed,
                    diagnostic: automationError.diagnosticKey
                )
            }
        }
    }

    private func beginAutomaticProxyRestoration(
        openSystemSettingsOnFailure: Bool,
        stopAfterRestoring: Bool
    ) {
        guard proxyAutomationTask == nil else { return }
        stopMonitor()
        proxyAutomationTask = Task { [weak self] in
            guard let self else { return }
            _ = await restoreSystemProxyAutomatically(
                openSystemSettingsOnFailure: openSystemSettingsOnFailure,
                stopAfterRestoring: stopAfterRestoring
            )
            proxyAutomationTask = nil
        }
    }

    private func restoreSystemProxyAutomatically(
        openSystemSettingsOnFailure: Bool,
        stopAfterRestoring: Bool
    ) async -> Bool {
        stopMonitor()
        do {
            let backup: BrowserDPIProxyBackup
            if let proxyBackup {
                backup = proxyBackup
            } else {
                backup = try await proxyAutomation.makeDisableBackup(
                    for: snapshot.endpoint
                )
                saveProxyBackup(backup)
            }
            guard !Task.isCancelled else { return false }
            publish(
                phase: .restoringSystemProxy,
                diagnostic: "",
                networkService: backup.networkService
            )
            try await proxyAutomation.restore(backup)
            guard !Task.isCancelled else { return false }

            if SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint),
               !(await waitForSystemProxy(active: false)) {
                throw BrowserDPIProxyAutomationError.commandFailed
            }

            clearProxyBackup()
            restoreSystemProxyForAppOnlyTransition = false
            if stopAfterRestoring {
                terminateImmediately()
            } else if process?.isRunning == true, requestedMode == .appOnly {
                startMonitor()
                publish(phase: .active, diagnostic: "", networkService: "")
            } else {
                publish(phase: .off, diagnostic: "")
            }
            return true
        } catch {
            let automationError = error as? BrowserDPIProxyAutomationError ?? .commandFailed
            publish(
                phase: .restoreRequired,
                diagnostic: automationError == .commandFailed
                    ? "Could not restore the previous proxy settings."
                    : automationError.diagnosticKey
            )
            if openSystemSettingsOnFailure {
                _ = openSystemProxySettings()
            }
            if process?.isRunning == true {
                startMonitor()
            }
            return false
        }
    }

    private func waitForSystemProxy(active: Bool) async -> Bool {
        for _ in 0..<30 {
            if Task.isCancelled { return false }
            let isActive = SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint)
            if isActive == active { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint) == active
    }

    private func waitForLocalProxyTermination() async {
        for _ in 0..<30 {
            guard process?.isRunning == true else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard let process, process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 {
            guard process.isRunning else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    func openSystemProxySettings() -> Bool {
        if environment["HITOMI_NATIVE_SKIP_EXTERNAL_OPEN"] == "1" {
            return true
        }
        if let networkSettings = URL(
            string: "x-apple.systempreferences:com.apple.Network-Settings.extension"
        ), NSWorkspace.shared.open(networkSettings) {
            return true
        }
        return NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        )
    }

    func prepareForTermination() {
        readinessTask?.cancel()
        readinessTask = nil
        proxyAutomationTask?.cancel()
        proxyAutomationTask = nil
        stopMonitor()
        if requiresProxyRestorationBeforeTermination {
            _ = openSystemProxySettings()
            return
        }
        terminateImmediately()
    }

    private func activateRequestedMode(openSystemSettings: Bool) {
        switch requestedMode {
        case .off:
            requestStop(openSystemSettings: openSystemSettings)
        case .appOnly:
            let needsRestoration = snapshot.hasRestorableProxySettings ||
                appOnlyTransitionProxyIsActive
            if needsRestoration {
                if automaticProxyConfigurationEnabled {
                    beginAutomaticProxyRestoration(
                        openSystemSettingsOnFailure: openSystemSettings,
                        stopAfterRestoring: false
                    )
                } else {
                    publish(
                        phase: .restoreRequired,
                        diagnostic: "Restore the macOS proxy settings to finish switching to App Only"
                    )
                    startMonitor()
                    if openSystemSettings {
                        _ = openSystemProxySettings()
                    }
                }
            } else {
                startMonitor()
                publish(phase: .active, diagnostic: "", networkService: "")
            }
        case .appAndBrowsers:
            if automaticProxyConfigurationEnabled {
                beginAutomaticProxyConfiguration(
                    openSystemSettingsOnFailure: openSystemSettings
                )
            } else {
                startMonitor()
                refreshSystemProxyState()
                if openSystemSettings, snapshot.phase != .active {
                    _ = openSystemProxySettings()
                }
            }
        }
    }

    private var appOnlyTransitionProxyIsActive: Bool {
        restoreSystemProxyForAppOnlyTransition &&
            SystemBrowserProxyDetector.currentSettingsUse(snapshot.endpoint)
    }

    nonisolated static func arguments(for endpoint: BrowserDPIProxyEndpoint) -> [String] {
        [
            "--clean",
            "--app-mode", "http",
            "--listen-addr", endpoint.displayValue,
            "--dns-mode", "https",
            "--dns-cache",
            "--https-split-mode", "chunk",
            "--https-chunk-size", "1",
            "--https-disorder",
            "--no-tui",
            "--log-level", "warn"
        ]
    }

    private var executableURL: URL? {
        if let override = environment["HITOMI_NATIVE_SPOOFDPI"]?.trimmed,
           !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("spoofdpi"),
              fileManager.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func selectAvailablePort() -> UInt16? {
        let preferred = proxyBackup?.endpoint.port ??
            Self.configuredPort(defaults: defaults, environment: environment)
        if Self.canBind(port: preferred) {
            return preferred
        }
        guard proxyBackup == nil else { return nil }
        guard environment["HITOMI_NATIVE_SPOOFDPI_PORT"] == nil else {
            return nil
        }
        return Self.defaultFallbackPorts.first(where: Self.canBind(port:))
    }

    private func startMonitor() {
        guard monitorTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refreshSystemProxyState()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func stopMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func terminateImmediately(
        finalPhase: BrowserDPIBypassPhase = .off,
        diagnostic: String = ""
    ) {
        stopAfterProxyRemoval = false
        stopMonitor()
        terminalPhaseAfterStop = (finalPhase, diagnostic)
        guard let process else {
            let terminal = terminalPhaseAfterStop ?? (.off, "")
            terminalPhaseAfterStop = nil
            publish(phase: terminal.0, diagnostic: terminal.1)
            return
        }
        intentionalStop = true
        if process.isRunning {
            process.interrupt()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
            }
        } else {
            processDidTerminate(process)
        }
    }

    private func processDidTerminate(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        process = nil
        readinessTask?.cancel()
        readinessTask = nil
        stopMonitor()
        closeLogHandle()
        let wasIntentional = intentionalStop
        intentionalStop = false
        stopAfterProxyRemoval = false
        if wasIntentional {
            let terminal = terminalPhaseAfterStop ?? (.off, "")
            terminalPhaseAfterStop = nil
            publish(phase: terminal.0, diagnostic: terminal.1)
        } else {
            terminalPhaseAfterStop = nil
            publish(
                phase: .failed,
                diagnostic: "SpoofDPI stopped unexpectedly."
            )
        }
    }

    private func closeLogHandle() {
        try? logHandle?.synchronize()
        try? logHandle?.close()
        logHandle = nil
    }

    private func saveProxyBackup(_ backup: BrowserDPIProxyBackup) {
        proxyBackup = backup
        if let data = try? JSONEncoder().encode(backup) {
            defaults.set(data, forKey: Self.proxyBackupKey)
        }
    }

    private func clearProxyBackup() {
        proxyBackup = nil
        defaults.removeObject(forKey: Self.proxyBackupKey)
    }

    private func publish(
        phase: BrowserDPIBypassPhase,
        diagnostic: String,
        networkService: String? = nil
    ) {
        let updated = BrowserDPIBypassSnapshot(
            phase: phase,
            endpoint: snapshot.endpoint,
            diagnostic: diagnostic,
            networkService: networkService ?? proxyBackup?.networkService ?? snapshot.networkService,
            hasRestorableProxySettings: proxyBackup != nil
        )
        guard updated != snapshot else { return }
        snapshot = updated
        onUpdate?(updated)
    }

    private nonisolated static func loadProxyBackup(
        defaults: UserDefaults
    ) -> BrowserDPIProxyBackup? {
        guard let data = defaults.data(forKey: proxyBackupKey) else { return nil }
        return try? JSONDecoder().decode(BrowserDPIProxyBackup.self, from: data)
    }

    private nonisolated static func configuredPort(
        defaults: UserDefaults,
        environment: [String: String]
    ) -> UInt16 {
        if let raw = environment["HITOMI_NATIVE_SPOOFDPI_PORT"]?.trimmed,
           let port = UInt16(raw), port > 0 {
            return port
        }
        let saved = defaults.integer(forKey: portKey)
        if let port = UInt16(exactly: saved), port > 0 {
            return port
        }
        return BrowserDPIProxyEndpoint.defaultPort
    }

    private nonisolated static func waitUntilListening(on port: UInt16) async -> Bool {
        for _ in 0..<40 {
            if Task.isCancelled { return false }
            if canConnect(port: port) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private nonisolated static func canBind(port: UInt16) -> Bool {
        withLoopbackSocket(port: port, operation: Darwin.bind)
    }

    private nonisolated static func canConnect(port: UInt16) -> Bool {
        withLoopbackSocket(port: port, operation: Darwin.connect)
    }

    private nonisolated static func withLoopbackSocket(
        port: UInt16,
        operation: (Int32, UnsafePointer<sockaddr>, socklen_t) -> Int32
    ) -> Bool {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                operation(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
