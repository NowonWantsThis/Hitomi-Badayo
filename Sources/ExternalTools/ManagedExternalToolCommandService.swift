import Foundation

enum ManagedExternalToolCommandEvent {
    case status(String)
    case summary(String)
    case installed(ManagedExternalToolInstallResult)
    case clearManagedPaths
}

@MainActor
final class ManagedExternalToolCommandService {
    typealias InstallOperation =
        (
            ExternalToolKind
        ) async throws -> ManagedExternalToolInstallResult
    typealias RemoveOperation =
        () async throws -> Void

    private let installOperation: InstallOperation
    private let removeOperation: RemoveOperation

    init(
        installOperation:
            @escaping InstallOperation = { kind in
                try await ManagedExternalToolInstaller
                    .shared.install(kind)
            },
        removeOperation:
            @escaping RemoveOperation = {
                try ManagedExternalToolInstaller
                    .shared.removeManagedTools()
            }
    ) {
        self.installOperation = installOperation
        self.removeOperation = removeOperation
    }

    func installingStatus(
        for kind: ExternalToolKind
    ) -> String {
        "Installing \(kind.displayName)…"
    }

    var removingStatus: String {
        "Removing Managed Tools…"
    }

    func install(
        _ kind: ExternalToolKind,
        emit: (ManagedExternalToolCommandEvent) -> Void
    ) async {
        do {
            let result = try await installOperation(kind)
            try Task.checkCancellation()
            emit(.installed(result))
            let version = String(
                result.version.prefix(100)
            )
            emit(.status(
                "\(kind.displayName) Ready: \(version)"
            ))
            emit(.summary(
                "\(kind.displayName) installed"
            ))
        } catch is CancellationError {
            let status = "Tool Installation Cancelled"
            emit(.status(status))
            emit(.summary(status))
        } catch {
            emit(.status(
                "\(kind.displayName) Installation Failed: \(AppLocalization.errorText(error))"
            ))
            emit(.summary(
                "\(kind.displayName) install failed"
            ))
        }
    }

    func installAll(
        emit: (ManagedExternalToolCommandEvent) -> Void
    ) async {
        do {
            for kind in [
                ExternalToolKind.aria2c,
                .ytdlp,
                .deno,
                .ffmpeg
            ] {
                try Task.checkCancellation()
                emit(.status(
                    "Installing \(kind.displayName)…"
                ))
                let result =
                    try await installOperation(kind)
                emit(.installed(result))
            }
            let status = "All Managed Tools Ready"
            emit(.status(status))
            emit(.summary(status))
        } catch is CancellationError {
            let status = "Tool Installation Cancelled"
            emit(.status(status))
            emit(.summary(status))
        } catch {
            emit(.status(
                "Tool Installation Failed: \(AppLocalization.errorText(error))"
            ))
            emit(.summary(
                "Tool installation failed"
            ))
        }
    }

    func remove(
        emit: (ManagedExternalToolCommandEvent) -> Void
    ) async {
        do {
            try await removeOperation()
            emit(.clearManagedPaths)
            emit(.status(
                "Managed Tools Removed · Bundled aria2c Remains Available"
            ))
            emit(.summary("Managed tools removed"))
        } catch {
            emit(.status(
                "Tool Removal Failed: \(AppLocalization.errorText(error))"
            ))
            emit(.summary("Tool removal failed"))
        }
    }
}
