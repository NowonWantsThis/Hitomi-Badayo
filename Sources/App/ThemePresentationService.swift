import SwiftUI

struct ThemePresentationSnapshot {
    let availableThemes: [PythonThemeDescriptor]
    let activeTheme: PythonThemeDescriptor?
    let preferredColorScheme: ColorScheme?
    let tintColor: Color
    let backgroundColor: Color?
    let surfaceColor: Color?
    let foregroundColor: Color?
}

enum ThemePresentationService {
    static func snapshot(
        plugins: [PythonScriptPlugin],
        selectedThemeKey: String,
        appearanceMode: AppAppearanceMode
    ) -> ThemePresentationSnapshot {
        let availableThemes = effectiveThemes(from: plugins)
        let normalizedKey = selectedThemeKey.trimmed.lowercased()
        let activeTheme = normalizedKey.isEmpty
            ? nil
            : availableThemes.first { $0.key == normalizedKey }
        let preferredColorScheme: ColorScheme?
        switch activeTheme?.appearance {
        case .light:
            preferredColorScheme = .light
        case .dark:
            preferredColorScheme = .dark
        case .system, .none:
            preferredColorScheme = colorScheme(for: appearanceMode)
        }

        return ThemePresentationSnapshot(
            availableThemes: availableThemes,
            activeTheme: activeTheme,
            preferredColorScheme: preferredColorScheme,
            tintColor: color(from: activeTheme?.accentColor) ?? .accentColor,
            backgroundColor: color(from: activeTheme?.backgroundColor),
            surfaceColor: color(from: activeTheme?.surfaceColor),
            foregroundColor: color(from: activeTheme?.foregroundColor)
        )
    }

    static func effectiveThemes(
        from plugins: [PythonScriptPlugin]
    ) -> [PythonThemeDescriptor] {
        var keyOrder: [String] = []
        var themesByKey: [String: PythonThemeDescriptor] = [:]
        let registrationOrder = plugins
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt {
                    return lhs.importedAt < rhs.importedAt
                }
                return lhs.digest < rhs.digest
            }
        for plugin in registrationOrder {
            for rawTheme in plugin.registeredThemes {
                guard let theme = rawTheme.normalized() else { continue }
                if themesByKey[theme.key] == nil {
                    keyOrder.append(theme.key)
                }
                themesByKey[theme.key] = theme
            }
        }
        return keyOrder.compactMap { themesByKey[$0] }
    }

    static func colorScheme(for mode: AppAppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private static func color(from value: String?) -> Color? {
        guard let value else { return nil }
        return Color(hexRGB: value)
    }
}
