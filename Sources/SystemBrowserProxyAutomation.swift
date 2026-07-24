import Foundation

struct BrowserDPIExecutableCommand: Equatable, Sendable {
    var executablePath: String
    var arguments: [String]
}

struct BrowserDPICommandResult: Equatable, Sendable {
    var terminationStatus: Int32
    var standardOutput: String
    var standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }

    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: "\n")
    }
}

protocol BrowserDPICommandRunning: Sendable {
    func run(_ command: BrowserDPIExecutableCommand) async -> BrowserDPICommandResult
    func runPrivileged(
        _ commands: [BrowserDPIExecutableCommand]
    ) async -> BrowserDPICommandResult
}

actor BrowserDPIProcessCommandRunner: BrowserDPICommandRunning {
    func run(_ command: BrowserDPIExecutableCommand) async -> BrowserDPICommandResult {
        await Self.execute(command)
    }

    func runPrivileged(
        _ commands: [BrowserDPIExecutableCommand]
    ) async -> BrowserDPICommandResult {
        let shellCommand = commands
            .map(Self.shellCommand)
            .joined(separator: " && ")
        let appleScript = "do shell script \(Self.appleScriptLiteral(shellCommand)) " +
            "with administrator privileges"
        return await Self.execute(BrowserDPIExecutableCommand(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        ))
    }

    private nonisolated static func execute(
        _ command: BrowserDPIExecutableCommand
    ) async -> BrowserDPICommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: command.executablePath)
            process.arguments = command.arguments
            process.standardOutput = standardOutput
            process.standardError = standardError
            var environment = ProcessInfo.processInfo.environment
            environment["LANG"] = "C"
            environment["LC_ALL"] = "C"
            process.environment = environment

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return BrowserDPICommandResult(
                    terminationStatus: -1,
                    standardOutput: "",
                    standardError: error.localizedDescription
                )
            }

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            return BrowserDPICommandResult(
                terminationStatus: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        }.value
    }

    nonisolated static func shellCommand(
        _ command: BrowserDPIExecutableCommand
    ) -> String {
        ([command.executablePath] + command.arguments)
            .map(shellQuote)
            .joined(separator: " ")
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

struct BrowserDPIProxyRecord: Codable, Equatable, Sendable {
    var enabled: Bool
    var server: String
    var port: Int
    var authenticated: Bool

    func matches(_ endpoint: BrowserDPIProxyEndpoint) -> Bool {
        guard enabled else { return false }
        let normalizedServer = server.trimmed.lowercased()
        let expectedServer = endpoint.host.trimmed.lowercased()
        let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        let hostMatches = normalizedServer == expectedServer ||
            (loopbackHosts.contains(normalizedServer) && loopbackHosts.contains(expectedServer))
        return hostMatches && port == Int(endpoint.port)
    }
}

struct BrowserDPIProxyBackup: Codable, Equatable, Sendable {
    var networkService: String
    var endpoint: BrowserDPIProxyEndpoint
    var webProxy: BrowserDPIProxyRecord
    var secureWebProxy: BrowserDPIProxyRecord
    var createdAt: Date
}

enum BrowserDPIProxyAutomationError: Error, Equatable, Sendable {
    case noActiveNetworkService
    case existingProxyConfiguration
    case authenticatedProxyConfiguration
    case authorizationCancelled
    case commandFailed

    var diagnosticKey: String {
        switch self {
        case .noActiveNetworkService:
            return "No active network service was found."
        case .existingProxyConfiguration:
            return "An existing system proxy is already active."
        case .authenticatedProxyConfiguration:
            return "An authenticated system proxy cannot be replaced automatically."
        case .authorizationCancelled:
            return "Administrator approval was cancelled."
        case .commandFailed:
            return "Could not update the macOS proxy settings."
        }
    }
}

actor SystemBrowserProxyAutomation {
    nonisolated static let networkSetupPath = "/usr/sbin/networksetup"
    nonisolated static let routePath = "/sbin/route"

    private let runner: any BrowserDPICommandRunning

    init(runner: any BrowserDPICommandRunning = BrowserDPIProcessCommandRunner()) {
        self.runner = runner
    }

    func makeBackup(
        for endpoint: BrowserDPIProxyEndpoint
    ) async throws -> BrowserDPIProxyBackup {
        let networkService = try await activeNetworkService()
        let webProxy = try await proxyRecord(
            commandName: "-getwebproxy",
            networkService: networkService
        )
        let secureWebProxy = try await proxyRecord(
            commandName: "-getsecurewebproxy",
            networkService: networkService
        )

        guard !webProxy.authenticated, !secureWebProxy.authenticated else {
            throw BrowserDPIProxyAutomationError.authenticatedProxyConfiguration
        }
        if (webProxy.enabled && !webProxy.matches(endpoint)) ||
            (secureWebProxy.enabled && !secureWebProxy.matches(endpoint)) {
            throw BrowserDPIProxyAutomationError.existingProxyConfiguration
        }

        var restorableWebProxy = webProxy
        var restorableSecureWebProxy = secureWebProxy
        if restorableWebProxy.matches(endpoint) {
            restorableWebProxy.enabled = false
        }
        if restorableSecureWebProxy.matches(endpoint) {
            restorableSecureWebProxy.enabled = false
        }

        return BrowserDPIProxyBackup(
            networkService: networkService,
            endpoint: endpoint,
            webProxy: restorableWebProxy,
            secureWebProxy: restorableSecureWebProxy,
            createdAt: Date()
        )
    }

    func apply(_ backup: BrowserDPIProxyBackup) async throws {
        let endpoint = backup.endpoint
        let result = await runner.runPrivileged([
            Self.networkSetupCommand(
                "-setwebproxy",
                backup.networkService,
                endpoint.host,
                String(endpoint.port),
                "off"
            ),
            Self.networkSetupCommand(
                "-setsecurewebproxy",
                backup.networkService,
                endpoint.host,
                String(endpoint.port),
                "off"
            )
        ])
        try Self.validatePrivilegedResult(result)
    }

    func restore(_ backup: BrowserDPIProxyBackup) async throws {
        var commands: [BrowserDPIExecutableCommand] = []
        commands.append(contentsOf: Self.restoreCommands(
            proxy: backup.webProxy,
            setter: "-setwebproxy",
            stateSetter: "-setwebproxystate",
            networkService: backup.networkService
        ))
        commands.append(contentsOf: Self.restoreCommands(
            proxy: backup.secureWebProxy,
            setter: "-setsecurewebproxy",
            stateSetter: "-setsecurewebproxystate",
            networkService: backup.networkService
        ))
        let result = await runner.runPrivileged(commands)
        try Self.validatePrivilegedResult(result)
    }

    func makeDisableBackup(
        for endpoint: BrowserDPIProxyEndpoint
    ) async throws -> BrowserDPIProxyBackup {
        let current = try await makeBackup(for: endpoint)
        return BrowserDPIProxyBackup(
            networkService: current.networkService,
            endpoint: endpoint,
            webProxy: BrowserDPIProxyRecord(
                enabled: false,
                server: current.webProxy.server,
                port: current.webProxy.port,
                authenticated: false
            ),
            secureWebProxy: BrowserDPIProxyRecord(
                enabled: false,
                server: current.secureWebProxy.server,
                port: current.secureWebProxy.port,
                authenticated: false
            ),
            createdAt: Date()
        )
    }

    nonisolated static func defaultInterface(from routeOutput: String) -> String? {
        for line in routeOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard trimmed.hasPrefix("interface:") else { continue }
            let value = String(trimmed.dropFirst("interface:".count)).trimmed
            if !value.isEmpty { return value }
        }
        return nil
    }

    nonisolated static func networkService(
        for device: String,
        serviceOrderOutput: String
    ) -> String? {
        var currentService: String?
        for line in serviceOrderOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            if trimmed.hasPrefix("("), !trimmed.hasPrefix("(Hardware Port:"),
               let closingParenthesis = trimmed.firstIndex(of: ")") {
                let nameStart = trimmed.index(after: closingParenthesis)
                let candidate = String(trimmed[nameStart...]).trimmed
                currentService = candidate.hasPrefix("*")
                    ? String(candidate.dropFirst()).trimmed
                    : candidate
                continue
            }
            guard trimmed.hasPrefix("(Hardware Port:"),
                  trimmed.contains("Device: \(device)"),
                  let currentService,
                  !currentService.isEmpty else {
                continue
            }
            return currentService
        }
        return nil
    }

    nonisolated static func proxyRecord(
        from output: String
    ) -> BrowserDPIProxyRecord? {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmed
            let valueStart = line.index(after: separator)
            values[key] = String(line[valueStart...]).trimmed
        }
        guard let enabledValue = values["Enabled"] else { return nil }
        return BrowserDPIProxyRecord(
            enabled: Self.boolValue(enabledValue),
            server: values["Server"] ?? "",
            port: Int(values["Port"] ?? "") ?? 0,
            authenticated: Self.boolValue(values["Authenticated Proxy Enabled"] ?? "0")
        )
    }

    private func activeNetworkService() async throws -> String {
        let routeResult = await runner.run(BrowserDPIExecutableCommand(
            executablePath: Self.routePath,
            arguments: ["-n", "get", "default"]
        ))
        guard routeResult.succeeded,
              let device = Self.defaultInterface(from: routeResult.standardOutput) else {
            throw BrowserDPIProxyAutomationError.noActiveNetworkService
        }

        let serviceResult = await runner.run(Self.networkSetupCommand(
            "-listnetworkserviceorder"
        ))
        guard serviceResult.succeeded,
              let service = Self.networkService(
                for: device,
                serviceOrderOutput: serviceResult.standardOutput
              ) else {
            throw BrowserDPIProxyAutomationError.noActiveNetworkService
        }
        return service
    }

    private func proxyRecord(
        commandName: String,
        networkService: String
    ) async throws -> BrowserDPIProxyRecord {
        let result = await runner.run(Self.networkSetupCommand(
            commandName,
            networkService
        ))
        guard result.succeeded,
              let proxy = Self.proxyRecord(from: result.standardOutput) else {
            throw BrowserDPIProxyAutomationError.commandFailed
        }
        return proxy
    }

    private nonisolated static func networkSetupCommand(
        _ arguments: String...
    ) -> BrowserDPIExecutableCommand {
        BrowserDPIExecutableCommand(
            executablePath: networkSetupPath,
            arguments: arguments
        )
    }

    private nonisolated static func restoreCommands(
        proxy: BrowserDPIProxyRecord,
        setter: String,
        stateSetter: String,
        networkService: String
    ) -> [BrowserDPIExecutableCommand] {
        var commands: [BrowserDPIExecutableCommand] = []
        if !proxy.server.trimmed.isEmpty, proxy.port > 0 {
            commands.append(networkSetupCommand(
                setter,
                networkService,
                proxy.server,
                String(proxy.port),
                "off"
            ))
        }
        commands.append(networkSetupCommand(
            stateSetter,
            networkService,
            proxy.enabled ? "on" : "off"
        ))
        return commands
    }

    private nonisolated static func validatePrivilegedResult(
        _ result: BrowserDPICommandResult
    ) throws {
        guard !result.succeeded else { return }
        let output = result.combinedOutput.lowercased()
        if result.terminationStatus == -128 ||
            output.contains("user canceled") ||
            output.contains("user cancelled") ||
            output.contains("(-128)") {
            throw BrowserDPIProxyAutomationError.authorizationCancelled
        }
        throw BrowserDPIProxyAutomationError.commandFailed
    }

    private nonisolated static func boolValue(_ value: String) -> Bool {
        ["1", "yes", "true", "on"].contains(value.trimmed.lowercased())
    }
}
