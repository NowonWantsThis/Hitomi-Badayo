import Foundation

struct PythonExecutionLogRecord: Equatable {
    let category: String
    let message: String
}

final class PythonExecutionLogService {
    func hookRecords(
        from text: String,
        pluginTitle: String,
        eventLabel: String
    ) -> [PythonExecutionLogRecord] {
        records(
            from: text,
            pluginTitle: pluginTitle,
            scope: eventLabel,
            category: "Hook"
        )
    }

    func scriptRecords(
        from text: String,
        pluginTitle: String,
        scope: String
    ) -> [PythonExecutionLogRecord] {
        records(
            from: text,
            pluginTitle: pluginTitle,
            scope: scope,
            category: "Script"
        )
    }

    private func records(
        from text: String,
        pluginTitle: String,
        scope: String,
        category: String
    ) -> [PythonExecutionLogRecord] {
        text
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .suffix(12)
            .map { line in
                PythonExecutionLogRecord(
                    category: category,
                    message:
                        "\(pluginTitle) [\(scope)]: " +
                        String(line.prefix(500))
                )
            }
    }
}
