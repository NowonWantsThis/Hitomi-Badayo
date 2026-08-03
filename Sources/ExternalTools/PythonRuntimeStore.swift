import Combine
import Foundation

@MainActor
final class PythonRuntimeStore: ObservableObject {
    @Published private(set) var scriptPlugins: [PythonScriptPlugin]
    @Published private(set) var scriptStatus: String
    @Published private(set) var hookStatus: String
    @Published private(set) var isReloadingScripts: Bool
    @Published private(set) var themeStatus: String

    init(
        scriptPlugins: [PythonScriptPlugin] = [],
        scriptStatus: String = "Python Scripts Not Loaded",
        hookStatus: String = "Hook Waiting",
        isReloadingScripts: Bool = false,
        themeStatus: String = "Default Theme"
    ) {
        self.scriptPlugins = scriptPlugins
        self.scriptStatus = scriptStatus
        self.hookStatus = hookStatus
        self.isReloadingScripts = isReloadingScripts
        self.themeStatus = themeStatus
    }

    func replaceScriptPlugins(with plugins: [PythonScriptPlugin]) {
        scriptPlugins = plugins
    }

    func appendScriptPlugin(_ plugin: PythonScriptPlugin) {
        scriptPlugins.append(plugin)
    }

    @discardableResult
    func updateScriptPlugin(
        id: String,
        _ update: (inout PythonScriptPlugin) -> Void
    ) -> PythonScriptPlugin? {
        guard let index = scriptPlugins.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        update(&scriptPlugins[index])
        return scriptPlugins[index]
    }

    @discardableResult
    func removeScriptPlugin(id: String) -> PythonScriptPlugin? {
        guard let index = scriptPlugins.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return scriptPlugins.remove(at: index)
    }

    func sortScriptPlugins(
        by areInIncreasingOrder: (PythonScriptPlugin, PythonScriptPlugin) -> Bool
    ) {
        scriptPlugins.sort(by: areInIncreasingOrder)
    }

    func setScriptStatus(_ status: String) {
        scriptStatus = status
    }

    func setHookStatus(_ status: String) {
        hookStatus = status
    }

    func setReloadingScripts(_ isReloading: Bool) {
        isReloadingScripts = isReloading
    }

    func setThemeStatus(_ status: String) {
        themeStatus = status
    }
}
