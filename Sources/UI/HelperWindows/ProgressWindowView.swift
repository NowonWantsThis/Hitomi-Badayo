import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProgressWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @Environment(\.queueControlCommands) private var queueCommands
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsStore: SettingsStore

    private var progress: QueueProgressPresentationSnapshot {
        QueueProgressPresentationService.snapshot(jobs: queueStore.jobs)
    }

    private var visibleJobs: [DownloadJob] {
        let jobs = progress.visibleJobs
        return jobs.isEmpty ? Array(queueStore.jobs.prefix(12)) : jobs
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            jobList
            Divider()
            footer
        }
        .frame(width: 720, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Progress")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(queueStore.isRunning ? "Queue running" : "Queue idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                navigation.closeProgress()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close progress")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(progress.statusText)
                    .font(.headline.monospacedDigit())
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded()))%")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .help("\(progress.completedUnits)/\(progress.totalUnits)")

            HStack(spacing: 10) {
                Label("\(queueStore.jobs.count) tasks", systemImage: "list.bullet.rectangle")
                Label("\(progress.activeJobs.count) active", systemImage: "bolt")
                Label("\(progress.completedUnits)/\(progress.totalUnits)", systemImage: "number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(18)
    }

    private var jobList: some View {
        Group {
            if visibleJobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "progress.indicator")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No tasks")
                        .font(.headline)
                    Text("Add URLs to the queue, then start downloads to see progress here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleJobs) { job in
                        ProgressWindowJobRow(job: job)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                queueCommands.start()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(queueStore.isRunning)

            Button {
                queueCommands.cancel()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .disabled(!queueStore.isRunning)

            Button {
                _ = manager.clearFinished()
            } label: {
                Label("Clear", systemImage: "checkmark.circle")
            }
            .disabled(
                queueStore.jobs.allSatisfy {
                    !QueuePresentationReadModelService
                        .isRemovableFinishedJob($0)
                } || queueStore.isRunning
            )

            Spacer()

            if !appStatusStore.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    appStatusStore.addSummary,
                    language: settingsStore.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct ProgressWindowJobRow: View {
    let job: DownloadJob

    private var units: (completed: Int, total: Int) {
        QueueProgressPresentationService.units(for: job)
    }

    private var fraction: Double {
        guard units.total > 0 else { return 0 }
        return min(1, max(0, Double(units.completed) / Double(units.total)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                    .frame(width: 18)

                Text(job.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)

            HStack(spacing: 8) {
                if let summary = job.partialFailureSummary() {
                    Text(summary)
                } else {
                    Text(job.statusDisplayText())
                    Text("\(units.completed)/\(units.total)")
                }
                if !job.message.trimmed.isEmpty {
                    Text(AppLocalization.statusText(job.message))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .help(job.source)
    }

    private var iconName: String {
        JobStatusStyle.iconName(for: job)
    }

    private var statusColor: Color {
        JobStatusStyle.color(for: job)
    }
}
