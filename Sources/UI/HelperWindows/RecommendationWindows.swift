import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ArtistRecommendationsView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var queueStore: QueueStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let recommendations = manager.visibleArtistRecommendations()

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label(localized("Artist Recommendations"), systemImage: "person.2")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(recommendations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(
                    localized("Filter artists"),
                    text: $searchStore.artistRecommendationFilter
                )
                    .textFieldStyle(.roundedBorder)
                if !searchStore.artistRecommendationFilter.trimmed.isEmpty {
                    Button {
                        manager.clearArtistRecommendationFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(localized("Clear filter"))
                }
                Button {
                    manager.clearHiddenArtistRecommendations()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(searchStore.hiddenArtistRecommendationIDs.isEmpty)
                .help(localized("Restore hidden artists"))
            }

            Divider()

            if recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("No artist signals yet"))
                        .font(.headline)
                    if !searchStore.artistRecommendationFilter.trimmed.isEmpty ||
                        !searchStore.hiddenArtistRecommendationIDs.isEmpty {
                        Text(localized("Clear the filter or restore hidden artists to show more recommendations."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(recommendations) { recommendation in
                        ArtistRecommendationRow(
                            recommendation: recommendation,
                            language: settingsStore.interfaceLanguage
                        ) {
                            manager.applyArtistRecommendation(recommendation)
                            dismiss()
                        } copy: {
                            manager.copyArtistRecommendation(recommendation)
                        } hide: {
                            manager.hideArtistRecommendation(recommendation)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .accessibilityIdentifier("auxiliary.artist-recommendations")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
    }
}

struct HitomiTasterWizardView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var searchStore: SearchStore

    var body: some View {
        let results = manager.visibleHitomiTasterResults()

        VStack(spacing: 0) {
            header(results: results)
            Divider()
            HSplitView {
                trainingPane
                    .frame(minWidth: 310, idealWidth: 360)
                resultsPane(results: results)
                    .frame(minWidth: 560)
            }
        }
        .frame(width: 980, height: 660)
        .onAppear {
            manager.refreshHitomiTasterReferenceCount()
        }
    }

    private func header(results: [HitomiTasterResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Hitomi Taster", systemImage: "brain.head.profile")
                    .font(.headline)
                Text(searchStore.hitomiTasterModel.originalLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    navigation.close(.hitomiTaster)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Hitomi Taster")
            }

            HStack(spacing: 8) {
                Picker("Model", selection: $searchStore.hitomiTasterModel) {
                    ForEach(HitomiTasterModel.allCases) { model in
                        Text(model.label)
                            .tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)

                Button {
                    manager.trainHitomiTaster()
                } label: {
                    Label("Train", systemImage: "play.fill")
                }
                .disabled(
                    searchStore.hitomiTasterReferenceCount <
                        searchStore.hitomiTasterModel.minimumReferenceCount
                )

                Button {
                    manager.exportHitomiTasterResults()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(searchStore.hitomiTasterResults.isEmpty)
                .help("Save results as XLSX")

                Button {
                    navigation.close(.hitomiTaster)
                    navigation.open(.artistRecommendations)
                } label: {
                    Image(systemName: "person.2")
                }
                .help("Open artist recommendations")

                Spacer()
                Label(
                    "\(searchStore.hitomiTasterReferenceCount)",
                    systemImage: "books.vertical"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(results.count)", systemImage: "person.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(accuracyText, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.bar)
    }

    private var trainingPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                Text(searchStore.hitomiTasterModel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Needs \(searchStore.hitomiTasterModel.minimumReferenceCount) reference works."
                )
                    .font(.caption2)
                    .foregroundStyle(referenceColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(searchStore.hitomiTasterStatus)
                        .font(.subheadline)
                    Spacer()
                    Text(
                        "\(Int((searchStore.hitomiTasterProgress * 100).rounded()))%"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: searchStore.hitomiTasterProgress)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Training Log")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if searchStore.hitomiTasterTrainingLog.isEmpty {
                            Text("Choose a model and train from local queue, history, and artist-tagged bookmarks.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(
                                Array(
                                    searchStore.hitomiTasterTrainingLog
                                        .enumerated()
                                ),
                                id: \.offset
                            ) { _, line in
                                Text(line)
                                    .foregroundStyle(line.hasPrefix("[ERROR]") ? .red : .primary)
                            }
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func resultsPane(results: [HitomiTasterResult]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(
                    "Filter results",
                    text: $searchStore.hitomiTasterFilter
                )
                    .textFieldStyle(.roundedBorder)
                if !searchStore.hitomiTasterFilter.trimmed.isEmpty {
                    Button {
                        manager.clearHitomiTasterFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                }
                Button {
                    manager.clearHiddenArtistRecommendations()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(searchStore.hiddenArtistRecommendationIDs.isEmpty)
                .help("Restore hidden artists")
            }
            .padding(12)

            Divider()

            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(
                        searchStore.hitomiTasterResults.isEmpty
                            ? "No Results Yet"
                            : "No Matching Artists"
                    )
                        .font(.headline)
                    Text(
                        searchStore.hitomiTasterResults.isEmpty
                            ? "Train the model to classify candidate artists."
                            : "Clear the filter or restore hidden artists."
                    )
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { result in
                        HitomiTasterResultRow(result: result) {
                            manager.applyHitomiTasterResult(result)
                            navigation.close(.hitomiTaster)
                        } copy: {
                            manager.copyHitomiTasterResult(result)
                        } hide: {
                            manager.hideHitomiTasterResult(result)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var referenceColor: Color {
        searchStore.hitomiTasterReferenceCount >=
            searchStore.hitomiTasterModel.minimumReferenceCount
            ? .secondary
            : .orange
    }

    private var accuracyText: String {
        searchStore.hitomiTasterAccuracy > 0
            ? "\(String(format: "%.1f", searchStore.hitomiTasterAccuracy))%"
            : "Not trained"
    }
}

struct HitomiTasterResultRow: View {
    let result: HitomiTasterResult
    let apply: () -> Void
    let copy: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(result.rank)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(scoreText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(confidenceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(signalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !result.relatedTerms.isEmpty {
                    Text(result.relatedTerms.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !result.exampleTitle.isEmpty {
                    Text(result.exampleTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy artist")

            Button(action: apply) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Use as search query")

            Button(action: hide) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Hide result")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                apply()
            } label: {
                Label("Use as Search Query", systemImage: "magnifyingglass")
            }
            Button {
                copy()
            } label: {
                Label("Copy Artist", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                hide()
            } label: {
                Label("Hide", systemImage: "xmark.circle")
            }
        }
    }

    private var scoreText: String {
        "score \(String(format: "%.2f", result.adjustedScore))"
    }

    private var confidenceText: String {
        "acc \(String(format: "%.1f", result.confidence))%"
    }

    private var signalText: String {
        [
            result.jobCount > 0 ? "\(result.jobCount) jobs" : nil,
            result.historyCount > 0 ? "\(result.historyCount) history" : nil,
            result.bookmarkCount > 0 ? "\(result.bookmarkCount) bookmarks" : nil,
            result.queryToken
        ].compactMap { $0 }.joined(separator: " - ")
    }
}

struct ArtistRecommendationRow: View {
    let recommendation: ArtistRecommendation
    let language: AppInterfaceLanguage
    let apply: () -> Void
    let copy: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recommendation.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(scoreText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !recommendation.relatedTerms.isEmpty {
                    Text(recommendation.relatedTerms.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !recommendation.exampleTitle.isEmpty {
                    Text(recommendation.exampleTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(localized("Copy artist"))

            Button(action: apply) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(localized("Use as search query"))

            Button(action: hide) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(localized("Hide recommendation"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                apply()
            } label: {
                Label(localized("Use as Search Query"), systemImage: "magnifyingglass")
            }
            Button {
                copy()
            } label: {
                Label(localized("Copy Artist"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                hide()
            } label: {
                Label(localized("Hide"), systemImage: "xmark.circle")
            }
        }
    }

    private var scoreText: String {
        String(format: "%.1f", recommendation.score)
    }

    private var countText: String {
        let parts = [
            recommendation.jobCount > 0
                ? AppLocalization.format("%@ jobs", language: language, String(recommendation.jobCount))
                : nil,
            recommendation.historyCount > 0
                ? AppLocalization.format("%@ history", language: language, String(recommendation.historyCount))
                : nil,
            recommendation.bookmarkCount > 0
                ? AppLocalization.format("%@ bookmarks", language: language, String(recommendation.bookmarkCount))
                : nil
        ].compactMap { $0 }
        return parts.isEmpty ? recommendation.queryToken : parts.joined(separator: " - ")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }
}
