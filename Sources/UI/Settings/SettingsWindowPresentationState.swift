import Combine

@MainActor
final class SettingsWindowPresentationState: ObservableObject {
    @Published var category: SettingsWindowCategory = .general
    @Published var filter = ""
    @Published var archiveFilter = ""
    @Published var browserDPIAdvancedExpanded = false
    @Published var pawchiveSiteAddressDraft = ""
    @Published var pawchiveSelectedSiteAddress = ""
    @Published var isAddingPawchiveSiteAddress = false
    @Published var newSiteRuleName = ""
    @Published var newSiteRuleHost = ""
    @Published var newSiteRuleURLPattern = ""
    @Published var newSiteRuleCommand = ""
    @Published var newSiteRuleReferer = ""
    @Published var newSiteRuleUserAgent = ""
    @Published var newSiteRuleArchiveMode: SiteArchiveMode = .default
    @Published var newSiteRuleDeleteOriginalAfterArchiving = false

    func prepare(category: SettingsWindowCategory) {
        self.category = category
    }

    func resetSiteRuleDraft() {
        newSiteRuleName = ""
        newSiteRuleHost = ""
        newSiteRuleURLPattern = ""
        newSiteRuleCommand = ""
        newSiteRuleReferer = ""
        newSiteRuleUserAgent = ""
        newSiteRuleArchiveMode = .default
        newSiteRuleDeleteOriginalAfterArchiving = false
    }
}
