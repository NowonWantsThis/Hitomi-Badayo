import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

struct LaunchAtLoginSettings {
    static let enabledKey = "launchAtLoginEnabled"
    private static let testSkipEnvironmentKey = "HITOMI_NATIVE_SKIP_LOGIN_ITEM_API"

    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    @discardableResult
    static func apply(enabled: Bool, defaults: UserDefaults = .standard) -> String {
        defaults.set(enabled, forKey: enabledKey)

        if ProcessInfo.processInfo.environment[testSkipEnvironmentKey] == "1" {
            return enabled ? "Launch at Login saved" : "Launch at Login off"
        }

        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    return "Launch at Login on"
                }
                try SMAppService.mainApp.unregister()
                return "Launch at Login off"
            } catch {
                return "Launch at Login saved, but macOS rejected registration"
            }
        }
        #endif

        return enabled ? "Launch at Login saved" : "Launch at Login off"
    }
}
