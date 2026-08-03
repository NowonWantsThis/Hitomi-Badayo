import Foundation

@MainActor
final class PythonHookExecutionService {
    typealias Runner = @MainActor (
        String,
        PythonScriptPlugin,
        PythonHookEvent,
        [String],
        PythonHookContext
    ) async throws -> PythonHookExecutionResult

    private let runner: Runner

    init(
        runner: @escaping Runner = {
            configuredPythonPath,
            plugin,
            event,
            names,
            context in
            try await PythonScriptBridge(
                configuredPythonPath: configuredPythonPath
            ).runHooks(
                plugin: plugin,
                event: event,
                names: names,
                context: context
            )
        }
    ) {
        self.runner = runner
    }

    func execute(
        event: PythonHookEvent,
        initialContext: PythonHookContext,
        calls: [EffectivePythonHookCall],
        configuredPythonPath: String,
        reportStatus: (String) -> Void,
        recordLogs: (
            String,
            PythonScriptPlugin,
            PythonHookEvent
        ) -> Void,
        errorText: (Error) -> String = {
            AppLocalization.errorText($0)
        }
    ) async throws -> PythonHookContext {
        guard !calls.isEmpty else { return initialContext }

        var context = initialContext
        var executed = 0
        reportStatus("Running \(event.shortLabel) Hook...")

        do {
            for call in calls {
                let result = try await runner(
                    configuredPythonPath,
                    call.plugin,
                    event,
                    call.names,
                    context
                )
                context = result.context
                executed += call.names.count
                recordLogs(result.logs, call.plugin, event)
            }
            reportStatus(
                "\(event.shortLabel.capitalized): \(executed) Hooks Executed"
            )
            return context
        } catch {
            reportStatus(
                "\(event.shortLabel.capitalized) Hook Failed: " +
                    errorText(error)
            )
            throw error
        }
    }
}
