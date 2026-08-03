import Foundation

enum FilterComparison: String {
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
}

enum FilterLexeme: Equatable {
    case term(String)
    case and
    case or
    case not
    case openGroup
    case closeGroup
}

enum FilterSyntaxCore {
    static func lexemes(from query: String) -> [FilterLexeme] {
        var lexemes: [FilterLexeme] = []
        var current = ""
        var quote: Character?

        func appendCurrent() {
            let piece = current.trimmed
            current = ""
            guard !piece.isEmpty else { return }
            switch piece.lowercased() {
            case "and":
                lexemes.append(.and)
            case "or":
                lexemes.append(.or)
            case "not":
                lexemes.append(.not)
            default:
                lexemes.append(.term(piece))
            }
        }

        for character in query {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
                continue
            }

            if quote == nil {
                switch character {
                case " ", "\t", "\n", "\r":
                    appendCurrent()
                    continue
                case ",":
                    appendCurrent()
                    lexemes.append(.and)
                    continue
                case "|", "+":
                    appendCurrent()
                    lexemes.append(.or)
                    continue
                case "&":
                    appendCurrent()
                    lexemes.append(.and)
                    continue
                case "!":
                    appendCurrent()
                    lexemes.append(.not)
                    continue
                case "(":
                    appendCurrent()
                    lexemes.append(.openGroup)
                    continue
                case ")":
                    appendCurrent()
                    lexemes.append(.closeGroup)
                    continue
                default:
                    break
                }
            }

            current.append(character)
        }

        appendCurrent()
        return lexemes
    }

    static func pieces(from query: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var quote: Character?

        for character in query {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
                continue
            }

            if quote == nil, character.isWhitespace || character == "," {
                if !current.trimmed.isEmpty {
                    pieces.append(current)
                }
                current = ""
            } else {
                current.append(character)
            }
        }

        if !current.trimmed.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    static func strippingQuotes(from value: String) -> String {
        let trimmed = value.trimmed
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" || first == "'"),
              first == last else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    static func inlineComparison(from value: String) -> (comparison: FilterComparison, threshold: String)? {
        let trimmed = value.trimmed
        for op in ["<=", ">=", "<", ">"] {
            guard trimmed.hasPrefix(op),
                  let comparison = FilterComparison(rawValue: op) else {
                continue
            }
            let threshold = String(trimmed.dropFirst(op.count)).trimmed
            return threshold.isEmpty ? nil : (comparison, threshold)
        }
        return nil
    }

    static func nonnegativeInteger(from raw: String) -> Int? {
        let compact = raw
            .trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard let value = Int(compact), value >= 0 else {
            return nil
        }
        return value
    }

    static func durationSeconds(from raw: String) -> Double? {
        let value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }

        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count >= 2, parts.count <= 3 else { return nil }
            var multiplier: Double = 1
            var total: Double = 0
            for part in parts.reversed() {
                guard let component = Double(part.trimmed), component >= 0 else { return nil }
                total += component * multiplier
                multiplier *= 60
            }
            return total
        }

        if let seconds = compoundDurationSeconds(from: value) {
            return seconds
        }

        if let number = Double(value), number >= 0 {
            return number
        }
        return nil
    }

    static func compoundDurationSeconds(from value: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(ms|h|m|s)"#, options: []) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return nil }

        var consumed = ""
        var total: Double = 0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: value),
                  let unitRange = Range(match.range(at: 2), in: value),
                  let wholeRange = Range(match.range, in: value),
                  let number = Double(String(value[numberRange])) else {
                return nil
            }
            let unit = String(value[unitRange])
            consumed += String(value[wholeRange])
            switch unit {
            case "ms":
                total += number / 1000
            case "h":
                total += number * 3600
            case "m":
                total += number * 60
            case "s":
                total += number
            default:
                return nil
            }
        }

        let compactValue = value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let compactConsumed = consumed.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return compactConsumed == compactValue ? total : nil
    }

    static func bool(_ flag: Bool, matches value: String) -> Bool {
        let trueValues = ["1", "true", "yes", "on", "pin", "pinned", "lock", "locked"]
        let falseValues = ["0", "false", "no", "off", "unpin", "unpinned", "unlock", "unlocked"]
        if trueValues.contains(value) { return flag }
        if falseValues.contains(value) { return !flag }
        return false
    }

    static func normalizedHost(from source: String) -> String {
        if let host = URL(string: source)?.host?.lowercased() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return ""
    }
}
