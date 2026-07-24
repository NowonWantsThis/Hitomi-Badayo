import Darwin
import Foundation

enum ExternalProcessRunnerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

final class ExternalProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var shouldTerminate = false
    private var shouldInterrupt = false
    private var suspended = false
    private var suspensionRequested = false

    var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suspended || suspensionRequested
    }

    var isRunning: Bool {
        lock.lock()
        let process = self.process
        lock.unlock()
        return process?.isRunning == true
    }

    var wasInterrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldInterrupt
    }

    func setProcess(_ process: Process) {
        lock.lock()
        if process.isRunning {
            self.process = process
        } else {
            self.process = nil
            suspended = false
            suspensionRequested = false
        }
        let terminateNow = shouldTerminate
        let interruptNow = shouldInterrupt
        if terminateNow || interruptNow {
            suspended = false
            suspensionRequested = false
        } else if process.isRunning, suspensionRequested, !suspended {
            let ok = Self.signal(process, SIGSTOP)
            suspended = ok
            if !ok {
                suspensionRequested = false
            }
        }
        lock.unlock()

        if terminateNow {
            terminate()
        } else if interruptNow {
            interrupt()
        }
    }

    func markTerminated(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
            suspended = false
            suspensionRequested = false
        }
        lock.unlock()
    }

    @discardableResult
    func suspend() -> Bool {
        lock.lock()
        guard let process, process.isRunning else {
            suspended = false
            lock.unlock()
            return false
        }
        if suspended {
            suspensionRequested = true
            lock.unlock()
            return true
        }
        suspensionRequested = true
        let ok = Self.signal(process, SIGSTOP)
        suspended = ok
        if !ok {
            suspensionRequested = false
        }
        lock.unlock()
        return ok
    }

    @discardableResult
    func suspendWhenAvailable() -> Bool {
        lock.lock()
        guard !shouldTerminate, !shouldInterrupt else {
            lock.unlock()
            return false
        }
        suspensionRequested = true
        guard let process, process.isRunning else {
            lock.unlock()
            return true
        }
        if suspended {
            lock.unlock()
            return true
        }
        let ok = Self.signal(process, SIGSTOP)
        suspended = ok
        if !ok {
            suspensionRequested = false
        }
        lock.unlock()
        return ok
    }

    @discardableResult
    func resume() -> Bool {
        lock.lock()
        let hadSuspensionRequest = suspensionRequested
        suspensionRequested = false
        guard let process, process.isRunning else {
            suspended = false
            lock.unlock()
            return hadSuspensionRequest
        }
        let wasSuspended = suspended
        suspended = false
        guard wasSuspended else {
            lock.unlock()
            return true
        }
        let ok = Self.signal(process, SIGCONT)
        if !ok {
            suspended = true
            suspensionRequested = true
        }
        lock.unlock()
        return ok
    }

    func terminate() {
        lock.lock()
        shouldTerminate = true
        let process = self.process
        let wasSuspended = suspended
        suspended = false
        suspensionRequested = false
        lock.unlock()

        guard let process, process.isRunning else { return }
        if wasSuspended {
            Self.signal(process, SIGCONT)
        }
        Self.signal(process, SIGTERM)
    }

    @discardableResult
    func interrupt(gracePeriod: TimeInterval = 10) -> Bool {
        lock.lock()
        shouldInterrupt = true
        let process = self.process
        let wasSuspended = suspended
        suspended = false
        suspensionRequested = false
        lock.unlock()

        guard let process, process.isRunning else { return false }
        let pid = process.processIdentifier
        if wasSuspended {
            Self.signal(process, SIGCONT)
        }
        let interrupted = Self.signal(process, SIGINT)
        guard interrupted, gracePeriod > 0 else { return interrupted }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + gracePeriod) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let sameProcessIsRunning = self.process?.processIdentifier == pid && self.process?.isRunning == true
            self.lock.unlock()
            if sameProcessIsRunning {
                self.terminate()
            }
        }
        return true
    }

    @discardableResult
    private static func signal(_ process: Process, _ signal: Int32) -> Bool {
        let pid = process.processIdentifier
        let processGroup = Darwin.getpgid(pid)
        if processGroup == pid {
            return Darwin.kill(-pid, signal) == 0
        }
        return Darwin.kill(pid, signal) == 0
    }
}

private enum ExternalProcessRuntimeRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var controls: [ObjectIdentifier: ExternalProcessControl] = [:]
    nonisolated(unsafe) private static var queuePausedControls: [ObjectIdentifier: ExternalProcessControl] = [:]
    nonisolated(unsafe) private static var queuePaused = false

    static func register(_ control: ExternalProcessControl) {
        let identifier = ObjectIdentifier(control)
        lock.lock()
        controls[identifier] = control
        let shouldPause = queuePaused
        lock.unlock()

        if shouldPause {
            pauseForQueue(control, identifier: identifier)
        }
    }

    static func unregister(_ control: ExternalProcessControl) {
        let identifier = ObjectIdentifier(control)
        lock.lock()
        controls.removeValue(forKey: identifier)
        let pausedControl = queuePausedControls.removeValue(forKey: identifier)
        lock.unlock()
        if pausedControl != nil {
            _ = control.resume()
        }
    }

    static func pauseAllForQueue() {
        lock.lock()
        queuePaused = true
        let activeControls = Array(controls)
        lock.unlock()

        for (identifier, control) in activeControls {
            pauseForQueue(control, identifier: identifier)
        }
    }

    static func resumeAllForQueue() {
        lock.lock()
        queuePaused = false
        let pausedControls = Array(queuePausedControls.values)
        queuePausedControls.removeAll()
        lock.unlock()

        pausedControls.forEach { _ = $0.resume() }
    }

    private static func pauseForQueue(
        _ control: ExternalProcessControl,
        identifier: ObjectIdentifier
    ) {
        guard !control.isSuspended, control.suspendWhenAvailable() else { return }

        lock.lock()
        let stillOwned = queuePaused && controls[identifier] === control
        if stillOwned {
            queuePausedControls[identifier] = control
        }
        lock.unlock()

        if !stillOwned {
            _ = control.resume()
        }
    }
}

enum ExternalProcessRunner {
    static func pauseAllForQueue() {
        ExternalProcessRuntimeRegistry.pauseAllForQueue()
    }

    static func resumeAllForQueue() {
        ExternalProcessRuntimeRegistry.resumeAllForQueue()
    }

    static func run(
        executable: URL,
        arguments: [String],
        logURL: URL,
        stdoutURL: URL? = nil,
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        control suppliedControl: ExternalProcessControl? = nil,
        acceptInterruptedTermination: Bool = false,
        failureDescription: String
    ) async throws {
        let state = suppliedControl ?? ExternalProcessControl()
        ExternalProcessRuntimeRegistry.register(state)
        defer { ExternalProcessRuntimeRegistry.unregister(state) }
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    let log = try FileHandle(forWritingTo: logURL)
                    let stdout: FileHandle?
                    if let stdoutURL {
                        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                        stdout = try FileHandle(forWritingTo: stdoutURL)
                    } else {
                        stdout = nil
                    }

                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.currentDirectoryURL = currentDirectoryURL
                    if !environment.isEmpty {
                        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
                    }
                    process.standardOutput = stdout ?? log
                    process.standardError = log
                    process.terminationHandler = { process in
                        state.markTerminated(process)
                        try? stdout?.synchronize()
                        try? stdout?.close()
                        try? log.synchronize()
                        try? log.close()
                        continuation.resume(returning: process.terminationStatus)
                    }

                    try process.run()
                    state.setProcess(process)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            state.terminate()
        }

        try Task.checkCancellation()

        guard status == 0 || (acceptInterruptedTermination && state.wasInterrupted) else {
            let logData = (try? Data(contentsOf: logURL)) ?? Data()
            let logText = String(decoding: logData, as: UTF8.self)
            let stdoutText: String
            if let stdoutURL,
               let stdoutData = try? Data(contentsOf: stdoutURL) {
                stdoutText = String(decoding: stdoutData, as: UTF8.self)
            } else {
                stdoutText = ""
            }
            let text = [logText, stdoutText]
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw ExternalProcessRunnerError.failed("\(failureDescription) failed (\(status)): \(tail(text))")
        }
    }

    private static func tail(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(6).joined(separator: " ")
        return tail.isEmpty ? "no diagnostic output" : tail
    }
}
