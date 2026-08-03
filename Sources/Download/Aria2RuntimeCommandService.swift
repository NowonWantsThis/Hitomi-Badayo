import Foundation

struct Aria2RuntimeCommandService: Sendable {
    typealias SpeedLimitChanger =
        @Sendable (
            Aria2RPCSession,
            String,
            String
        ) async throws -> [String: String]
    typealias FileSelectionChanger =
        @Sendable (
            Aria2RPCSession,
            String
        ) async throws -> [String: String]
    typealias SeedingChanger =
        @Sendable (
            Aria2RPCSession,
            String,
            String
        ) async throws -> [String: String]
    typealias PeerLoader =
        @Sendable (
            Aria2RPCSession
        ) async throws -> [Aria2PeerEntry]

    private let speedLimitChanger:
        SpeedLimitChanger
    private let fileSelectionChanger:
        FileSelectionChanger
    private let seedingChanger: SeedingChanger
    private let peerLoader: PeerLoader

    init(
        speedLimitChanger:
            @escaping SpeedLimitChanger = {
                try await Aria2RPCClient
                    .changeSpeedLimits(
                        session: $0,
                        downloadLimit: $1,
                        uploadLimit: $2
                    )
            },
        fileSelectionChanger:
            @escaping FileSelectionChanger = {
                try await Aria2RPCClient
                    .changeFileSelection(
                        session: $0,
                        selectedFiles: $1
                    )
            },
        seedingChanger:
            @escaping SeedingChanger = {
                try await Aria2RPCClient
                    .changeSeeding(
                        session: $0,
                        seedTimeMinutes: $1,
                        seedRatio: $2
                    )
            },
        peerLoader:
            @escaping PeerLoader = {
                try await Aria2RPCClient
                    .peerEntries(session: $0)
            }
    ) {
        self.speedLimitChanger =
            speedLimitChanger
        self.fileSelectionChanger =
            fileSelectionChanger
        self.seedingChanger = seedingChanger
        self.peerLoader = peerLoader
    }

    func changeSpeedLimits(
        session: Aria2RPCSession,
        downloadLimit: String,
        uploadLimit: String
    ) async throws -> [String: String] {
        try await speedLimitChanger(
            session,
            downloadLimit,
            uploadLimit
        )
    }

    func changeFileSelection(
        session: Aria2RPCSession,
        selectedFiles: String
    ) async throws -> [String: String] {
        try await fileSelectionChanger(
            session,
            selectedFiles
        )
    }

    func changeSeeding(
        session: Aria2RPCSession,
        seedTimeMinutes: String,
        seedRatio: String
    ) async throws -> [String: String] {
        try await seedingChanger(
            session,
            seedTimeMinutes,
            seedRatio
        )
    }

    func peerEntries(
        session: Aria2RPCSession
    ) async throws -> [Aria2PeerEntry] {
        try await peerLoader(session)
    }
}

@MainActor
final class Aria2RuntimeCommandCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeCommandCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        operation:
            @escaping @MainActor () async -> Void
    ) -> UUID {
        let commandID = UUID()
        tasks[commandID] =
            Task { @MainActor [weak self] in
                await operation()
                self?.finish(commandID)
            }
        return commandID
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    private func finish(_ commandID: UUID) {
        tasks.removeValue(forKey: commandID)
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
