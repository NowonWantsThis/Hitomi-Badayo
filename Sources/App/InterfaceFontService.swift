import AppKit
import Foundation

@MainActor
final class InterfaceFontService {
    typealias FamilyProvider = () -> [String]

    private let familyProvider:
        FamilyProvider

    init(
        familyProvider:
            @escaping FamilyProvider = {
                NSFontManager.shared
                    .availableFontFamilies
            }
    ) {
        self.familyProvider = familyProvider
    }

    func familyOptions() -> [String] {
        let families =
            familyProvider()
                .map(\.trimmed)
                .filter { !$0.isEmpty }
        return ["System"] +
            Array(Set(families)).sorted {
                $0.localizedCaseInsensitiveCompare(
                    $1
                ) == .orderedAscending
            }
    }

    func normalizedFamily(
        _ family: String
    ) -> String {
        let trimmed = family.trimmed
        guard !trimmed.isEmpty,
          trimmed.caseInsensitiveCompare(
            "system"
          ) != .orderedSame else {
            return ""
        }
        let available =
            Set(familyOptions().dropFirst())
        return available.contains(trimmed)
            ? trimmed
            : ""
    }
}
