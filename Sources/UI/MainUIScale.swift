import SwiftUI

struct MainUIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var mainUIScale: CGFloat {
        get { self[MainUIScaleKey.self] }
        set { self[MainUIScaleKey.self] = min(2, max(0.5, newValue)) }
    }
}

struct UIScaledRoot<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: () -> Content

    private var effectiveScale: CGFloat {
        min(2, max(0.5, CGFloat(scale)))
    }

    var body: some View {
        content()
            .environment(\.mainUIScale, effectiveScale)
    }
}
