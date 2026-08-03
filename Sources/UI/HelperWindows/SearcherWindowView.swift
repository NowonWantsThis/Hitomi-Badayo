import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SearcherWindowView: View {
    let manager: DownloadManager
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var searchStore: SearchStore
    let hostSize: CGSize
    @Environment(\.dismiss) private var dismiss

    private var layout: SearcherLayoutMetrics {
        SearcherLayoutPolicy.metrics(forHostSize: hostSize)
    }

    private var searchPresentation: SearchPresentationSnapshot {
        SearchPresentationReadModelService.snapshot(
            results: searchStore.searchResults,
            filter: searchStore.searchResultFilter,
            knownFilter: settingsStore.searchResultKnownFilter,
            sortMode: settingsStore.searchResultSortMode,
            sortDescending: settingsStore.searchResultSortDescending,
            jobs: queueStore.jobs,
            history: libraryStore.history,
            destinationPath: settingsStore.destinationPath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Searcher", systemImage: "text.magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(searchStore.searchProviders.count) providers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    manager.cancelSearchResultsFetch()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            searchBar

            TabView {
                resultsTab
                    .tabItem {
                        Label("Results", systemImage: "list.bullet.rectangle")
                    }

                savedSearchesTab
                    .tabItem {
                        Label("Saved", systemImage: "bookmark")
                    }

                providersTab
                    .tabItem {
                        Label("Providers", systemImage: "magnifyingglass.circle")
                    }

                tagsTab
                    .tabItem {
                        Label("Tags", systemImage: "tag")
                    }
            }
        }
        .padding(20)
        .frame(width: layout.width, height: layout.height)
        .onDisappear {
            manager.cancelSearchResultsFetch()
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $searchStore.selectedSearchProviderID) {
                    ForEach(searchStore.searchProviders) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: layout.usesCompactControls ? 132 : 180)
                .disabled(searchStore.searchProviders.isEmpty)
                .accessibilityIdentifier("searcher.provider")

                TextField("Query", text: $searchStore.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("searcher.query")
                    .onSubmit {
                        manager.fetchSearchResults()
                    }

                Button {
                    manager.openSearchURL()
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open search URL")

                Button {
                    manager.enqueueSearchURL()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add search URL to queue")

                Button {
                    manager.saveCurrentSearchBookmark()
                } label: {
                    Image(systemName: "bookmark")
                }
                .disabled(
                    searchStore.searchQuery.trimmed.isEmpty ||
                        searchStore.searchProviders.isEmpty
                )
                .help("Save search")

                Button {
                    if searchStore.isSearching {
                        manager.cancelSearchResultsFetch()
                    } else {
                        manager.fetchSearchResults()
                    }
                } label: {
                    Image(
                        systemName: searchStore.isSearching
                            ? "xmark"
                            : "arrow.clockwise"
                    )
                }
                .help(
                    searchStore.isSearching
                        ? "Cancel search"
                        : "Fetch results"
                )
                .accessibilityIdentifier("searcher.fetch")
            }

            hitomiAdvancedSearchBuilder

            HStack(spacing: 12) {
                Toggle("Dedup", isOn: Binding(
                    get: { settingsStore.searchDeduplicateResults },
                    set: { manager.setSearchDeduplicateResults($0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Hide Done", isOn: Binding(
                    get: { settingsStore.searchHideKnownResults },
                    set: { manager.setSearchHideKnownResults($0) }
                ))
                .toggleStyle(.checkbox)

                if !appStatusStore.addSummary.trimmed.isEmpty {
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
        }
    }

    private var hitomiAdvancedSearchBuilder: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 108), spacing: 8),
            count: layout.usesCompactControls ? 2 : 4
        )

        return DisclosureGroup(isExpanded: Binding(
            get: { searchStore.hitomiAdvancedSearchExpanded },
            set: { searchStore.hitomiAdvancedSearchExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, spacing: 8) {
                    TextField("Title", text: $searchStore.hitomiAdvancedTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Artist", text: $searchStore.hitomiAdvancedArtist)
                        .textFieldStyle(.roundedBorder)
                    TextField("Group", text: $searchStore.hitomiAdvancedGroup)
                        .textFieldStyle(.roundedBorder)
                    TextField("Series", text: $searchStore.hitomiAdvancedSeries)
                        .textFieldStyle(.roundedBorder)
                    TextField("Character", text: $searchStore.hitomiAdvancedCharacter)
                        .textFieldStyle(.roundedBorder)
                    TextField("Tag", text: $searchStore.hitomiAdvancedTag)
                        .textFieldStyle(.roundedBorder)
                    TextField("Language", text: $searchStore.hitomiAdvancedLanguage)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $searchStore.hitomiAdvancedLanguagePreset) {
                        ForEach(HitomiAdvancedLanguagePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                }

                if layout.usesCompactControls {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        advancedSearchTypeToggles
                        Toggle("No Webtoon", isOn: $searchStore.hitomiAdvancedExcludeWebtoon)
                            .toggleStyle(.checkbox)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        advancedSearchActionButtons
                    }
                } else {
                    HStack(spacing: 10) {
                        advancedSearchTypeToggles
                        Toggle("No Webtoon", isOn: $searchStore.hitomiAdvancedExcludeWebtoon)
                            .toggleStyle(.checkbox)
                        Spacer(minLength: 8)
                        advancedSearchActionButtons
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Hitomi Advanced", systemImage: "slider.horizontal.3")
                .font(.caption)
        }
        .accessibilityIdentifier("searcher.advanced")
    }

    @ViewBuilder
    private var advancedSearchTypeToggles: some View {
        ForEach(HitomiAdvancedSearchType.allCases) { type in
            Toggle(type.label, isOn: Binding(
                get: { searchStore.hitomiAdvancedTypes.contains(type) },
                set: { searchStore.setHitomiAdvancedSearchType(type, enabled: $0) }
            ))
            .toggleStyle(.checkbox)
        }
    }

    private var advancedSearchActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                manager.applyHitomiAdvancedSearchQuery()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .help("Apply Hitomi advanced query")

            Button {
                manager.appendHitomiAdvancedSearchQuery()
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("Append Hitomi advanced query")

            Button {
                manager.clearHitomiAdvancedSearchFields()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Clear Hitomi advanced fields")
        }
    }

    private var resultsTab: some View {
        let visibleResults = searchPresentation.filteredResults
        let knownState = searchPresentation.knownState

        return VStack(alignment: .leading, spacing: 10) {
            if layout.usesCompactControls {
                VStack(spacing: 6) {
                    resultFilterField
                    HStack(spacing: 6) {
                        resultFilterControls
                        Spacer(minLength: 4)
                        resultCountAndActions(visibleResults: visibleResults)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    resultFilterField
                    resultFilterControls
                    Spacer()
                    resultCountAndActions(visibleResults: visibleResults)
                }
            }

            if visibleResults.isEmpty {
                Text(
                    searchStore.searchResults.isEmpty
                        ? "No search results"
                        : "No matching results"
                )
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleResults) { result in
                        SearchResultRow(
                            result: result,
                            galleryID: DownloadManager.searchResultGalleryID(for: result),
                            metadataCopies: DownloadManager.searchResultMetadataCopies(for: result),
                            dateText: DownloadManager.searchResultDateText(for: result),
                            pageCountText: DownloadManager.searchResultPageCountText(for: result),
                            isDone: DownloadManager.searchResultIsKnown(result, knownState: knownState),
                            canOpenFirstOutput: DownloadManager.searchResultFirstOutputOpenURL(for: result, knownState: knownState) != nil,
                            enqueue: {
                                manager.enqueueSearchResult(result)
                            },
                            openSource: {
                                manager.openSearchResult(result)
                            },
                            copyURL: {
                                manager.copySearchResultURL(result)
                            },
                            copyTitle: {
                                manager.copySearchResultTitle(result)
                            },
                            copyMetadata: {
                                manager.copySearchResultMetadata($0)
                            },
                            openFirstOutput: {
                                manager.openFirstOutputFile(forSearchResult: result)
                            },
                            copyGalleryID: {
                                manager.copySearchResultGalleryID(result)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var resultFilterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Filter results", text: $searchStore.searchResultFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("searcher.result-filter")
            Button {
                searchStore.searchResultFilter = ""
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(searchStore.searchResultFilter.trimmed.isEmpty)
            .help("Clear filter")
        }
    }

    private var resultFilterControls: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { settingsStore.searchResultKnownFilter },
                set: { manager.setSearchResultKnownFilter($0) }
            )) {
                ForEach(SearchResultKnownFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 105)
            .help("Downloaded result filter")
            .accessibilityIdentifier("searcher.known-filter")

            Picker("", selection: Binding(
                get: { settingsStore.searchResultSortMode },
                set: { manager.setSearchResultSortMode($0) }
            )) {
                ForEach(SearchResultSortMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: layout.usesCompactControls ? 104 : 120)
            .accessibilityIdentifier("searcher.sort")

            Button {
                manager.setSearchResultSortDescending(
                    !settingsStore.searchResultSortDescending
                )
            } label: {
                Image(
                    systemName: settingsStore.searchResultSortDescending
                        ? "arrow.down"
                        : "arrow.up"
                )
            }
            .help(
                settingsStore.searchResultSortDescending
                    ? "Descending order"
                    : "Ascending order"
            )
        }
    }

    private func resultCountAndActions(visibleResults: [SearchResultLink]) -> some View {
        HStack(spacing: 6) {
            Text(
                (searchStore.searchResultFilter.trimmed.isEmpty &&
                    settingsStore.searchResultKnownFilter == .all)
                    ? "\(searchStore.searchResults.count)"
                    : "\(visibleResults.count)/\(searchStore.searchResults.count)"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                manager.enqueueAllSearchResults()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(visibleResults.isEmpty)
            .help("Add all visible results")

            Button {
                manager.cancelSearchResultsFetch()
                searchStore.clearSearchResults()
                searchStore.searchResultFilter = ""
                manager.setSearchResultKnownFilter(.all)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(searchStore.searchResults.isEmpty)
            .help("Clear results")
        }
    }

    private var savedSearchesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Searches")
                    .font(.headline)
                Spacer()
                Text("\(searchStore.searchBookmarks.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Menu {
                    Button {
                        manager.importSearchBookmarks()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchBookmarks()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(searchStore.searchBookmarks.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if searchStore.searchBookmarks.isEmpty {
                Text("No saved searches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchStore.searchBookmarks) { bookmark in
                        SearchBookmarkRow(
                            bookmark: bookmark,
                            apply: {
                                manager.applySearchBookmark(bookmark)
                            },
                            enqueue: {
                                manager.enqueueSearchBookmark(bookmark)
                            },
                            remove: {
                                manager.removeSearchBookmark(bookmark)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField(
                    "Provider",
                    text: $searchStore.newSearchProviderName
                )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: layout.usesCompactControls ? 132 : 180)
                TextField(
                    "https://site/search?q={query}",
                    text: $searchStore.newSearchProviderTemplate
                )
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.addSearchProvider()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Save provider")
                Button {
                    manager.resetSearchProviders()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset providers")
                Menu {
                    Button {
                        manager.importSearchProviders()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchProviders()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(searchStore.searchProviders.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if searchStore.searchProviders.isEmpty {
                Text("No search providers")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(
                        Array(searchStore.searchProviders.enumerated()),
                        id: \.element.id
                    ) { index, provider in
                        SearchProviderRow(
                            provider: provider,
                            canMoveUp: index > 0,
                            canMoveDown:
                                index < searchStore.searchProviders.count - 1,
                            moveUp: {
                                manager.moveSearchProvider(provider, by: -1)
                            },
                            moveDown: {
                                manager.moveSearchProvider(provider, by: 1)
                            },
                            remove: {
                                manager.removeSearchProvider(provider)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var tagsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(
                    "Hitomi excluded tags",
                    text: $settingsStore.hitomiExcludedTagsText
                )
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveHitomiExcludedTags()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save excluded tags")
                Button {
                    manager.clearHitomiExcludedTags()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(settingsStore.hitomiExcludedTagsText.trimmed.isEmpty)
                .help("Clear excluded tags")
            }

            HStack(spacing: 6) {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Translate tag", text: $searchStore.searchTagTranslationInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.translateSearchTagInput()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Translate tag")
                Button {
                    manager.insertTranslatedSearchTag()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Insert translated tag")
                Button {
                    manager.replaceSearchQueryWithTranslatedTag()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Replace query")
                Button {
                    manager.clearSearchTagTranslation()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(
                    searchStore.searchTagTranslationInput.trimmed.isEmpty &&
                        searchStore.searchTagTranslationOutput.trimmed.isEmpty
                )
                .help("Clear translation")
            }

            if !searchStore.searchTagTranslationOutput.trimmed.isEmpty {
                Text(searchStore.searchTagTranslationOutput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if searchStore.searchTagAutocompleteSuggestions.isEmpty {
                Text("No tag suggestions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchStore.searchTagAutocompleteSuggestions.prefix(50)) { suggestion in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(suggestion.token)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                manager.applySearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Use suggestion")
                            Button {
                                manager.insertSearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Insert suggestion")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }
}
