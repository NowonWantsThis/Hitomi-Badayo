import SwiftUI

struct CompactLinearProgress: View {
    let value: Double
    var color: Color = .accentColor
    @Environment(\.mainUIScale) private var uiScale

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4 * uiScale)
        .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent")
    }
}

struct ClockwiseDownloadIndicator: View {
    var color: Color
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(reduceMotion ? 0 : cycle * 360))
        }
        .accessibilityLabel(AppLocalization.text("Downloading"))
    }
}
