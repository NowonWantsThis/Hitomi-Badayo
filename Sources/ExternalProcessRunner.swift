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

    var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suspended
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
        }
        let terminateNow = shouldTerminate
        let interruptNow = shouldInterrupt
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
        let pid = process.processIdentifier
        suspended = true
        lock.unlock()

        let ok = Darwin.kill(pid, SIGSTOP) == 0
        if !ok {
            lock.lock()
            if self.process?.processIdentifier == pid {
                suspended = false
            }
            lock.unlock()
        }
        return ok
    }

    @discardableResult
    func resume() -> Bool {
        lock.lock()
        guard let process, process.isRunning else {
            suspended = false
            lock.unlock()
            return false
        }
        let pid = process.processIdentifier
        let wasSuspended = suspended
        suspended = false
        lock.unlock()

        guard wasSuspended else { return true }
        let ok = Darwin.kill(pid, SIGCONT) == 0
        if !ok {
            lock.lock()
            if self.process?.processIdentifier == pid {
                suspended = true
            }
            lock.unlock()
        }
        return ok
    }

    func terminate() {
        lock.lock()
        shouldTerminate = true
        let process = self.process
        let wasSuspended = suspended
        suspended = false
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

enum ExternalProcessRunner {
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
