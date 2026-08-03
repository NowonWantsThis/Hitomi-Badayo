import Combine
import Foundation

@MainActor
final class SearchStore: ObservableObject {
    @Published private(set) var searchProviders: [SearchProvider]
    @Published private(set) var searchBookmarks: [SearchBookmark]
    @Published private(set) var searchResults: [SearchResultLink]

    @Published var selectedSearchProviderID: UUID
    @Published var searchQuery: String
    @Published var newSearchProviderName: String
    @Published var newSearchProviderTemplate: String
    @Published var searchResultFilter: String
    @Published var isSearching: Bool
    @Published var hitomiAdvancedSearchExpanded: Bool
    @Published var hitomiAdvancedTitle: String
    @Published var hitomiAdvancedArtist: String
    @Published var hitomiAdvancedGroup: String
    @Published var hitomiAdvancedSeries: String
    @Published var hitomiAdvancedCharacter: String
    @Published var hitomiAdvancedTag: String
    @Published var hitomiAdvancedLanguage: String
    @Published var hitomiAdvancedLanguagePreset: HitomiAdvancedLanguagePreset
    @Published var hitomiAdvancedExcludeWebtoon: Bool
    @Published var hitomiAdvancedTypes: Set<HitomiAdvancedSearchType>
    @Published var searchTagTranslationInput: String
    @Published var searchTagTranslationOutput: String
    @Published var metadataFinderField: MetadataFinderField
    @Published var metadataFinderMode: MetadataFinderMode
    @Published var metadataFinderQuery: String
    @Published var metadataAnalysisField: MetadataAnalysisField
    @Published var artistRecommendationFilter: String
    @Published private(set) var hiddenArtistRecommendationIDs: Set<String>
    @Published var hitomiTasterModel: HitomiTasterModel
    @Published var hitomiTasterFilter: String
    @Published var hitomiTasterResults: [HitomiTasterResult]
    @Published var hitomiTasterStatus: String
    @Published var hitomiTasterProgress: Double
    @Published var hitomiTasterReferenceCount: Int
    @Published var hitomiTasterAccuracy: Double
    @Published var hitomiTasterTrainingLog: [String]

    init(
        searchProviders: [SearchProvider] = SearchProvider.defaultProviders,
        searchBookmarks: [SearchBookmark] = [],
        searchResults: [SearchResultLink] = [],
        selectedSearchProviderID: UUID? = nil,
        searchQuery: String = "",
        newSearchProviderName: String = "",
        newSearchProviderTemplate: String = "",
        searchResultFilter: String = "",
        isSearching: Bool = false,
        hitomiAdvancedSearchExpanded: Bool = false,
        hitomiAdvancedTitle: String = "",
        hitomiAdvancedArtist: String = "",
        hitomiAdvancedGroup: String = "",
        hitomiAdvancedSeries: String = "",
        hitomiAdvancedCharacter: String = "",
        hitomiAdvancedTag: String = "",
        hitomiAdvancedLanguage: String = "",
        hitomiAdvancedLanguagePreset: HitomiAdvancedLanguagePreset = .all,
        hitomiAdvancedExcludeWebtoon: Bool = false,
        hitomiAdvancedTypes: Set<HitomiAdvancedSearchType> = [],
        searchTagTranslationInput: String = "",
        searchTagTranslationOutput: String = "",
        metadataFinderField: MetadataFinderField = .artist,
        metadataFinderMode: MetadataFinderMode = .plain,
        metadataFinderQuery: String = "",
        metadataAnalysisField: MetadataAnalysisField = .artist,
        artistRecommendationFilter: String = "",
        hiddenArtistRecommendationIDs: Set<String> = [],
        hitomiTasterModel: HitomiTasterModel = .shallow,
        hitomiTasterFilter: String = "",
        hitomiTasterResults: [HitomiTasterResult] = [],
        hitomiTasterStatus: String = "Ready",
        hitomiTasterProgress: Double = 0,
        hitomiTasterReferenceCount: Int = 0,
        hitomiTasterAccuracy: Double = 0,
        hitomiTasterTrainingLog: [String] = []
    ) {
        self.searchProviders = searchProviders
        self.searchBookmarks = searchBookmarks
        self.searchResults = searchResults
        self.selectedSearchProviderID = selectedSearchProviderID
            ?? searchProviders.first?.id
            ?? SearchProvider.defaultProviders[0].id
        self.searchQuery = searchQuery
        self.newSearchProviderName = newSearchProviderName
        self.newSearchProviderTemplate = newSearchProviderTemplate
        self.searchResultFilter = searchResultFilter
        self.isSearching = isSearching
        self.hitomiAdvancedSearchExpanded = hitomiAdvancedSearchExpanded
        self.hitomiAdvancedTitle = hitomiAdvancedTitle
        self.hitomiAdvancedArtist = hitomiAdvancedArtist
        self.hitomiAdvancedGroup = hitomiAdvancedGroup
        self.hitomiAdvancedSeries = hitomiAdvancedSeries
        self.hitomiAdvancedCharacter = hitomiAdvancedCharacter
        self.hitomiAdvancedTag = hitomiAdvancedTag
        self.hitomiAdvancedLanguage = hitomiAdvancedLanguage
        self.hitomiAdvancedLanguagePreset = hitomiAdvancedLanguagePreset
        self.hitomiAdvancedExcludeWebtoon = hitomiAdvancedExcludeWebtoon
        self.hitomiAdvancedTypes = hitomiAdvancedTypes
        self.searchTagTranslationInput = searchTagTranslationInput
        self.searchTagTranslationOutput = searchTagTranslationOutput
        self.metadataFinderField = metadataFinderField
        self.metadataFinderMode = metadataFinderMode
        self.metadataFinderQuery = metadataFinderQuery
        self.metadataAnalysisField = metadataAnalysisField
        self.artistRecommendationFilter = artistRecommendationFilter
        self.hiddenArtistRecommendationIDs = hiddenArtistRecommendationIDs
        self.hitomiTasterModel = hitomiTasterModel
        self.hitomiTasterFilter = hitomiTasterFilter
        self.hitomiTasterResults = hitomiTasterResults
        self.hitomiTasterStatus = hitomiTasterStatus
        self.hitomiTasterProgress = hitomiTasterProgress
        self.hitomiTasterReferenceCount = hitomiTasterReferenceCount
        self.hitomiTasterAccuracy = hitomiTasterAccuracy
        self.hitomiTasterTrainingLog = hitomiTasterTrainingLog
    }

    var searchTagAutocompleteSuggestions: [SearchTagSuggestion] {
        SearchTagTranslationService.suggestions(for: searchTagTranslationInput)
    }

    var hitomiAdvancedSearchQuery: String {
        SearchTagTranslationService.advancedSearchQuery(
            title: hitomiAdvancedTitle,
            artist: hitomiAdvancedArtist,
            group: hitomiAdvancedGroup,
            series: hitomiAdvancedSeries,
            character: hitomiAdvancedCharacter,
            tag: hitomiAdvancedTag,
            language: hitomiAdvancedLanguage,
            types: hitomiAdvancedTypes,
            languagePreset: hitomiAdvancedLanguagePreset,
            excludeWebtoon: hitomiAdvancedExcludeWebtoon
        )
    }

    var translatedSearchTag: String {
        if !searchTagTranslationOutput.trimmed.isEmpty {
            return searchTagTranslationOutput.trimmed
        }
        return SearchTagTranslationService.translatedQueryTags(
            from: searchTagTranslationInput
        )
    }

    func replaceSearchProviders(with replacement: [SearchProvider]) {
        searchProviders = replacement
    }

    func updateSearchProviders(
        _ update: (inout [SearchProvider]) -> Void
    ) {
        update(&searchProviders)
    }

    func replaceSearchBookmarks(with replacement: [SearchBookmark]) {
        searchBookmarks = replacement
    }

    func updateSearchBookmarks(
        _ update: (inout [SearchBookmark]) -> Void
    ) {
        update(&searchBookmarks)
    }

    func replaceSearchResults(with replacement: [SearchResultLink]) {
        searchResults = replacement
    }

    func clearSearchResults() {
        searchResults.removeAll()
    }

    func setHitomiAdvancedSearchType(
        _ type: HitomiAdvancedSearchType,
        enabled: Bool
    ) {
        if enabled {
            hitomiAdvancedTypes.insert(type)
        } else {
            hitomiAdvancedTypes.remove(type)
        }
    }

    func clearHitomiAdvancedSearchFields() {
        hitomiAdvancedTitle = ""
        hitomiAdvancedArtist = ""
        hitomiAdvancedGroup = ""
        hitomiAdvancedSeries = ""
        hitomiAdvancedCharacter = ""
        hitomiAdvancedTag = ""
        hitomiAdvancedLanguage = ""
        hitomiAdvancedLanguagePreset = .all
        hitomiAdvancedExcludeWebtoon = false
        hitomiAdvancedTypes.removeAll()
    }

    func clearSearchTagTranslation() {
        searchTagTranslationInput = ""
        searchTagTranslationOutput = ""
    }

    func visibleArtistRecommendations(
        from recommendations: [ArtistRecommendation],
        limit: Int
    ) -> [ArtistRecommendation] {
        let query = artistRecommendationFilter.trimmed.lowercased()
        return recommendations
            .filter { recommendation in
                !hiddenArtistRecommendationIDs.contains(recommendation.id) &&
                    (query.isEmpty ||
                        recommendation.searchText.lowercased().contains(query))
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    func hideArtistRecommendation(id: String) {
        hiddenArtistRecommendationIDs.insert(id)
    }

    func clearHiddenArtistRecommendations() {
        hiddenArtistRecommendationIDs.removeAll()
    }

    func clearArtistRecommendationFilter() {
        artistRecommendationFilter = ""
    }

    func visibleHitomiTasterResults(limit: Int) -> [HitomiTasterResult] {
        let query = hitomiTasterFilter.trimmed.lowercased()
        return hitomiTasterResults
            .filter { result in
                !hiddenArtistRecommendationIDs.contains(
                    result.recommendation.id
                ) &&
                    (query.isEmpty ||
                        result.searchText.lowercased().contains(query))
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    func clearHitomiTasterFilter() {
        hitomiTasterFilter = ""
    }
}
