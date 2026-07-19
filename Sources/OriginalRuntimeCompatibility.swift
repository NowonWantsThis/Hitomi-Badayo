import Foundation

enum OriginalRuntimeCompatibility {
    static let ytdlpIsolationArguments = ["--ignore-config", "--no-plugin-dirs"]

    static func restartDelaySeconds(from comment: String) -> TimeInterval? {
        let pattern = #"restart:([^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(comment.startIndex..<comment.endIndex, in: comment)
        guard let match = regex.firstMatch(in: comment, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: comment) else {
            return nil
        }
        return parseTimeString(String(comment[valueRange]))
    }

    static func parseTimeString(_ rawValue: String) -> TimeInterval? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty else { return nil }

        if !value.contains(where: \Character.isLetter) {
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
            let values = pieces.compactMap { TimeInterval(String($0)) }
            guard values.count == pieces.count,
                  values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                return nil
            }

            var seconds: TimeInterval = 0
            for (index, part) in values.enumerated() {
                if values.count == 4 && index == 1 {
                    seconds = seconds * 24 + part
                } else {
                    seconds = seconds * 60 + part
                }
            }
            return seconds.isFinite ? seconds : nil
        }

        let pattern = #"([0-9]+(?:\.[0-9]+)?)([smhdw])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return nil }

        let multipliers: [Character: TimeInterval] = [
            "s": 1,
            "m": 60,
            "h": 3_600,
            "d": 86_400,
            "w": 604_800
        ]
        var seconds: TimeInterval = 0
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 1), in: value),
                  let unitRange = Range(match.range(at: 2), in: value),
                  let amount = TimeInterval(value[numberRange]),
                  amount.isFinite,
                  let unit = value[unitRange].first,
                  let multiplier = multipliers[unit] else {
                return nil
            }
            seconds += amount * multiplier
        }
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
