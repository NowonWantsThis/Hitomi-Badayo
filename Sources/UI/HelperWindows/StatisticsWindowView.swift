import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsView: View {
    let manager: DownloadManager
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var networkStore: NetworkStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var language: AppInterfaceLanguage { settingsStore.interfaceLanguage }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            let statistics = manager.statisticsSnapshot()
            content(statistics)
        }
    }

    private func content(_ statistics: AppStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label(localized("Info & Statistics"), systemImage: "chart.bar.xaxis")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(dateText(statistics.generatedAt, dateStyle: .none, timeStyle: .medium))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            StatisticsMonitorPanel(statistics: statistics, language: language)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("App") {
                        statRow("Name", statistics.appName)
                        statRow("Version", "\(statistics.appVersion) (\(statistics.appBuild))")
                        statRow("Bundle ID", statistics.bundleIdentifier)
                        statRow("Requires macOS", statistics.minimumSystemVersion)
                        statRow("Running On", operatingSystemText(statistics.operatingSystemVersion))
                    }

                    section("Paths") {
                        statRow("Downloads", statistics.outputRootPath.isEmpty ? localized("Not set") : statistics.outputRootPath)
                        statRow("App Support", statistics.applicationSupportPath)
                        statRow("User Data", statistics.userDataPath)
                    }

                    section("Tools") {
                        ForEach(statistics.externalTools) { tool in
                            statRow(tool.name, toolStatusText(tool))
                        }
                    }

                    section("Queue") {
                        statRow("Total", "\(statistics.totalJobs)")
                        statRow("Active", "\(statistics.activeJobs)")
                        statRow("Queued", "\(statistics.queuedJobs)")
                        statRow("Resolving", "\(statistics.resolvingJobs)")
                        statRow("Downloading", "\(statistics.downloadingJobs)")
                        statRow("Finished", "\(statistics.finishedJobs)")
                        statRow("Failed", "\(statistics.failedJobs)")
                        statRow("Cancelled", "\(statistics.cancelledJobs)")
                        statRow("Pinned", "\(statistics.pinnedJobs)")
                        statRow("Locked", "\(statistics.lockedJobs)")
                        statRow("Task Slots", "\(statistics.jobConcurrency)")
                        statRow("File Threads", "\(statistics.fileConcurrency)")
                        statRow("UI Scale", statistics.uiScale)
                    }

                    section("Runtime") {
                        statRow("Started", dateText(statistics.appStartedAt, dateStyle: .medium, timeStyle: .medium))
                        statRow("Elapsed", elapsedText(statistics.appUptimeSeconds))
                        statRow("Download Speed", transferSpeedText(statistics.downloadSpeedBytesPerSecond))
                        statRow("Upload Speed", transferSpeedText(statistics.uploadSpeedBytesPerSecond))
                        statRow("Downloaded Since Launch", optionalByteText(statistics.downloadedSinceLaunchByteCount))
                    }

                    section("Library") {
                        statRow("History", "\(statistics.historyCount)")
                        statRow("Bookmarks", "\(statistics.bookmarkCount)")
                        statRow("Filter Bookmarks", "\(statistics.queueFilterBookmarkCount)")
                        statRow(
                            "Site Rules",
                            AppLocalization.format(
                                "%@ / %@ enabled",
                                language: language,
                                String(statistics.enabledSiteRuleCount),
                                String(statistics.siteRuleCount)
                            )
                        )
                        statRow("Search Providers", "\(statistics.searchProviderCount)")
                        statRow("Duplicate Groups", "\(statistics.duplicateGroupCount)")
                        statRow("Duplicate Extras", "\(statistics.duplicateExtraFileCount)")
                    }

                    section("Output") {
                        statRow("Available", statistics.destinationPathAnalysisSkipped ? localized("Skipped") : optionalByteText(statistics.destinationAvailableByteCount))
                        statRow("Volume Size", statistics.destinationPathAnalysisSkipped ? localized("Skipped") : optionalByteText(statistics.destinationTotalByteCount))
                        statRow("Known Queue Size", byteText(statistics.estimatedQueuedByteCount))
                        statRow("Known Paths", "\(statistics.outputPathCount)")
                        statRow("Files", countedText(statistics.outputFileCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        statRow("Folders", countedText(statistics.outputDirectoryCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        statRow("Total Size", byteText(statistics.outputByteCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        if statistics.outputPathAnalysisSkippedCount > 0 {
                            statRow("Skipped Paths", "\(statistics.outputPathAnalysisSkippedCount)")
                        }
                        statRow("Auto Remove Finished", onOff(statistics.autoRemoveFinishedJobs))
                        statRow("Auto Remove Hook", optionText(statistics.autoRemoveHookCommand))
                        statRow("Auto Remove Hook Status", AppLocalization.statusText(appStatusStore.autoRemoveHookStatus, language: language))
                        statRow("Download Date", onOff(statistics.showDownloadDate))
                        if !statistics.diskSpaceWarning.isEmpty {
                            statRow("Warning", AppLocalization.statusText(statistics.diskSpaceWarning, language: language))
                        }
                    }

                    section("aria2 / Network") {
                        statRow("Download Limit", optionText(statistics.aria2MaxDownloadLimit))
                        statRow("Upload Limit", optionText(statistics.aria2MaxUploadLimit))
                        statRow("Seed Time", seedTimeText(statistics))
                        statRow("Seed Ratio", optionText(statistics.aria2SeedRatio))
                        statRow("Anonymous Mode", onOff(statistics.aria2AnonymousMode))
                        statRow("HTTP API", onOff(statistics.httpAPIEnabled))
                        statRow("Public IP", AppLocalization.statusText(statistics.publicIPStatus, language: language))
                        statRow("Clipboard Watch", onOff(statistics.clipboardMonitorEnabled))
                        statRow("YouTube Thumbnail", onOff(statistics.youtubeDownloadThumbnail))
                        statRow("YouTube Reverse Playlist", onOff(statistics.youtubeReversePlaylist))
                        statRow("YouTube Upload Date File Time", onOff(statistics.youtubeUseUploadDateForFileModificationTime))
                        statRow("YouTube Auto Subtitles", onOff(statistics.youtubeDownloadAutoSubtitles))
                        statRow("YouTube Subtitle Languages", optionText(statistics.youtubeSubtitleLanguages))
                        statRow("YouTube Chapters", onOff(statistics.youtubeEmbedChapters))
                        statRow("YouTube Codec Priority", optionText(statistics.youtubeVideoCodecSort))
                        statRow("YouTube Enhanced Bitrate", onOff(statistics.youtubePreferEnhancedBitrate))
                        statRow("YouTube Resolution", optionText(statistics.youtubePreferredResolution))
                        statRow("YouTube Audio Track", optionText(statistics.youtubePreferredAudioLanguage))
                        statRow("History", onOff(statistics.historyEnabled))
                        statRow("Prevent Sleep", onOff(statistics.preventSleepWhileDownloading))
                        statRow("Sleep Assertion", localized(appStatusStore.sleepPreventionActive ? "Active" : "Inactive"))
                    }

                    section("Alerts") {
                        statRow("Finished Job Notification", onOff(statistics.notifyWhenJobCompletes))
                        statRow("Queue Complete Notification", onOff(statistics.notifyWhenQueueCompletes))
                        statRow("Finished Job Sound", onOff(statistics.playSoundWhenJobCompletes))
                        statRow("Clipboard Add Sound", onOff(statistics.playSoundOnClipboardAdd))
                        statRow("After Queue Complete", AppLocalization.statusText(statistics.queueCompletionAction, language: language))
                        statRow("After Complete Status", AppLocalization.statusText(appStatusStore.queueCompletionActionStatus, language: language))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 560)
        .accessibilityIdentifier("auxiliary.statistics")
    }

    private func seedTimeText(_ statistics: AppStatistics) -> String {
        let value = statistics.aria2SeedTimeMinutes.trimmed
        if value.isEmpty || value == "0" {
            return localized("Off")
        }
        return AppLocalization.format("%@ min", language: language, value)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized(title))
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(localized(title))
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func byteText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func byteText(_ byteCount: Int64, partial: Bool) -> String {
        let text = byteText(byteCount)
        return partial ? AppLocalization.format("%@ counted", language: language, text) : text
    }

    private func countedText(_ count: Int, partial: Bool) -> String {
        partial ? AppLocalization.format("%@ counted", language: language, String(count)) : String(count)
    }

    private func optionalByteText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Unknown") }
        return byteText(byteCount)
    }

    private func transferSpeedText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Measuring") }
        return "\(byteText(byteCount))/s"
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remaining = totalSeconds % 60
        if hours > 0 {
            return AppLocalization.format(
                "%@h %@m %@s",
                language: language,
                String(hours),
                String(minutes),
                String(remaining)
            )
        }
        if minutes > 0 {
            return AppLocalization.format(
                "%@m %@s",
                language: language,
                String(minutes),
                String(remaining)
            )
        }
        return AppLocalization.format("%@s", language: language, String(remaining))
    }

    private func optionText(_ value: String) -> String {
        value.trimmed.isEmpty
            ? localized("Not set")
            : AppLocalization.statusText(value.trimmed, language: language)
    }

    private func onOff(_ enabled: Bool) -> String {
        localized(enabled ? "On" : "Off")
    }

    private func toolStatusText(_ tool: ExternalToolStatus) -> String {
        guard tool.isAvailable else {
            return tool.configuredPath.isEmpty
                ? localized("Not found")
                : AppLocalization.format("Missing: %@", language: language, tool.configuredPath)
        }
        if tool.configuredPath.isEmpty {
            return AppLocalization.format("Found: %@", language: language, tool.resolvedPath)
        }
        return AppLocalization.format("Configured: %@", language: language, tool.resolvedPath)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }

    private func dateText(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private func operatingSystemText(_ rawValue: String) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let components = [version.majorVersion, version.minorVersion, version.patchVersion]
        let lastIndex = version.patchVersion == 0 ? 1 : 2
        let versionText = components[0...lastIndex].map(String.init).joined(separator: ".")
        if let buildRange = rawValue.range(
            of: #"[0-9]{2}[A-Za-z][A-Za-z0-9]+"#,
            options: .regularExpression
        ) {
            return AppLocalization.format(
                "Version %@ (Build %@)",
                language: language,
                versionText,
                String(rawValue[buildRange])
            )
        }
        return AppLocalization.format("Version %@", language: language, versionText)
    }
}

private struct StatisticsMonitorPanel: View {
    let statistics: AppStatistics
    let language: AppInterfaceLanguage

    private var downloadFraction: Double {
        AppStatistics.speedFraction(statistics.downloadSpeedBytesPerSecond)
    }

    private var uploadFraction: Double {
        AppStatistics.speedFraction(statistics.uploadSpeedBytesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                usageColumn(
                    title: localized("Download"),
                    value: transferSpeedText(statistics.downloadSpeedBytesPerSecond),
                    fraction: downloadFraction,
                    color: .accentColor
                )

                usageColumn(
                    title: localized("Upload"),
                    value: transferSpeedText(statistics.uploadSpeedBytesPerSecond),
                    fraction: uploadFraction,
                    color: .orange
                )
            }

            StatisticsPlotView(values: [
                (label: "DL", fraction: downloadFraction, color: .accentColor),
                (label: "UL", fraction: uploadFraction, color: .orange),
                (label: localized("Active"), fraction: statistics.queueActiveFraction, color: .blue),
                (label: localized("Done"), fraction: statistics.queueCompletedFraction, color: .green),
                (label: localized("Disk"), fraction: statistics.destinationUsedFraction ?? 0, color: .purple)
            ])
            .frame(height: 78)

            HStack(spacing: 14) {
                Label(optionalByteText(statistics.downloadedSinceLaunchByteCount), systemImage: "arrow.down.circle")
                    .help(localized("Downloaded since launch"))
                Label(elapsedText(statistics.appUptimeSeconds), systemImage: "timer")
                    .help(localized("Elapsed time"))
                Label(
                    AppLocalization.format("%@ active", language: language, String(statistics.activeJobs)),
                    systemImage: "bolt"
                )
                    .help(localized("Resolving and downloading jobs"))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func usageColumn(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(2, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .frame(height: 10)
        }
    }

    private func byteText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func optionalByteText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Downloaded unknown") }
        return AppLocalization.format("%@ downloaded", language: language, byteText(byteCount))
    }

    private func transferSpeedText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Measuring") }
        return "\(byteText(byteCount))/s"
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remaining = totalSeconds % 60
        if hours > 0 {
            return AppLocalization.format(
                "%@h %@m %@s",
                language: language,
                String(hours),
                String(minutes),
                String(remaining)
            )
        }
        if minutes > 0 {
            return AppLocalization.format(
                "%@m %@s",
                language: language,
                String(minutes),
                String(remaining)
            )
        }
        return AppLocalization.format("%@s", language: language, String(remaining))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }
}

private struct StatisticsPlotView: View {
    let values: [(label: String, fraction: Double, color: Color)]

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(6, geometry.size.width / CGFloat(max(values.count, 1)) - 14)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .controlBackgroundColor))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(value.color)
                                .frame(height: max(2, (geometry.size.height - 20) * CGFloat(min(1, max(0, value.fraction)))))
                        }
                        .frame(width: barWidth, height: max(28, geometry.size.height - 20))

                        Text(value.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
