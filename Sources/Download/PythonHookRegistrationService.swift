import Foundation

struct EffectivePythonHookCall: Equatable {
    var plugin: PythonScriptPlugin
    var names: [String]
}

final class PythonHookRegistrationService {
    func calls(
        for event: PythonHookEvent,
        matchingNames: Set<String>? = nil,
        plugins: [PythonScriptPlugin]
    ) -> [EffectivePythonHookCall] {
        var nameOrder: [String] = []
        var owners: [String: PythonScriptPlugin] = [:]
        let registrationOrder = plugins
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt {
                    return lhs.importedAt < rhs.importedAt
                }
                return lhs.digest < rhs.digest
            }
        for plugin in registrationOrder {
            for hook in plugin.registeredHooks
            where hook.event == event &&
                (matchingNames?.contains(hook.name) ?? true) {
                if owners[hook.name] == nil {
                    nameOrder.append(hook.name)
                }
                owners[hook.name] = plugin
            }
        }

        var calls: [EffectivePythonHookCall] = []
        for name in nameOrder {
            guard let plugin = owners[name] else { continue }
            if calls.last?.plugin.id == plugin.id {
                calls[calls.count - 1].names.append(name)
            } else {
                calls.append(
                    EffectivePythonHookCall(
                        plugin: plugin,
                        names: [name]
                    )
                )
            }
        }
        return calls
    }
}
