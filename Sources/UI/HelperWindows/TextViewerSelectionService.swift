import Foundation

struct TextViewerSelectionService {
    func visibleEntries(
        in entries: [TextViewerEntry],
        filter: String
    ) -> [TextViewerEntry] {
        let query = filter.trimmed.lowercased()
        guard !query.isEmpty else {
            return entries
        }
        return entries.filter {
            $0.searchText.lowercased().contains(query)
        }
    }

    func ensuredSelectionID(
        in visibleEntries: [TextViewerEntry],
        currentSelectionID: String
    ) -> String {
        if visibleEntries.contains(where: {
            $0.id == currentSelectionID
        }) {
            return currentSelectionID
        }
        return visibleEntries.first?.id ?? ""
    }

    func selectedEntry(
        in entries: [TextViewerEntry],
        visibleEntries: [TextViewerEntry],
        selectedEntryID: String
    ) -> TextViewerEntry? {
        if let selected = entries.first(where: {
            $0.id == selectedEntryID
        }) {
            return selected
        }
        return visibleEntries.first
    }
}
