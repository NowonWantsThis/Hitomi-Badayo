import Foundation

struct DirectSegmentDirective:
    Equatable,
    Sendable
{
    var enabled: Bool?
    var count: Int?

    var normalized:
        DirectSegmentDirective {
        if enabled == false {
            return DirectSegmentDirective(
                enabled: false,
                count: nil
            )
        }
        if let count,
           count > 1 {
            return DirectSegmentDirective(
                enabled: true,
                count: count
            )
        }
        return DirectSegmentDirective(
            enabled: enabled,
            count: nil
        )
    }
}

enum DirectSegmentPlanningService {
    static func segments(
        from response: HTTPURLResponse,
        directive: DirectSegmentDirective? = nil
    ) -> [DirectSplitSegment]? {
        if directive?.enabled == false {
            return nil
        }

        let acceptsRanges =
            response
            .value(
                forHTTPHeaderField:
                    "Accept-Ranges"
            )?
            .lowercased() ?? ""
        guard acceptsRanges.contains("bytes") else {
            return nil
        }

        let encoding =
            response
            .value(
                forHTTPHeaderField:
                    "Content-Encoding"
            )?
            .lowercased()
            .trimmed ?? ""
        guard encoding.isEmpty ||
                encoding == "identity" else {
            return nil
        }

        guard let lengthText =
                response
                .value(
                    forHTTPHeaderField:
                        "Content-Length"
                )?
                .trimmed,
              let contentLength =
                Int(lengthText),
              contentLength > 1 else {
            return nil
        }

        if let count = directive?.count,
           count > 1 {
            return segments(
                contentLength: contentLength,
                count: count
            )
        }

        let chunkSize: Int
        if directive?.enabled == true,
           contentLength <=
            defaultChunkSize {
            chunkSize =
                max(
                    1,
                    Int(
                        ceil(
                            Double(
                                contentLength
                            ) / 2.0
                        )
                    )
                )
        } else {
            guard contentLength >
                    defaultChunkSize else {
                return nil
            }
            chunkSize = defaultChunkSize
        }
        return segments(
            contentLength: contentLength,
            chunkSize: chunkSize
        )
    }

    static func directive(
        from comment: String
    ) -> DirectSegmentDirective? {
        let lines =
            comment
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .components(
                separatedBy: "\n"
            )

        var inSegmentBlock = false
        var directive =
            DirectSegmentDirective()
        var found = false

        for rawLine in lines {
            let line = rawLine.trimmed
            guard !line.isEmpty else {
                inSegmentBlock = false
                continue
            }

            let lower = line.lowercased()
            if lower.hasPrefix("segment:") ||
                lower.hasPrefix("segment=") {
                found = true
                inSegmentBlock = true
                let separator =
                    line.firstIndex(
                        where: {
                            $0 == ":" ||
                                $0 == "="
                        }
                    )!
                let value =
                    String(
                        line[
                            line.index(
                                after: separator
                            )...
                        ]
                    )
                    .trimmed
                apply(
                    value,
                    to: &directive
                )
                continue
            }

            if inSegmentBlock,
               line.contains("=") {
                apply(
                    line,
                    to: &directive
                )
            } else {
                inSegmentBlock = false
            }
        }

        return found
            ? directive.normalized
            : nil
    }

    private static func segments(
        contentLength: Int,
        count rawCount: Int
    ) -> [DirectSplitSegment]? {
        let count =
            max(
                2,
                min(
                    rawCount,
                    contentLength
                )
            )
        let chunkSize =
            max(
                1,
                Int(
                    ceil(
                        Double(contentLength) /
                            Double(count)
                    )
                )
            )
        return segments(
            contentLength: contentLength,
            chunkSize: chunkSize
        )
    }

    private static func segments(
        contentLength: Int,
        chunkSize: Int
    ) -> [DirectSplitSegment]? {
        var segments:
            [DirectSplitSegment] = []
        var lowerBound = 0
        var index = 1
        while lowerBound < contentLength {
            let upperBound =
                min(
                    contentLength - 1,
                    lowerBound +
                        chunkSize -
                        1
                )
            segments.append(
                DirectSplitSegment(
                    index: index,
                    lowerBound: lowerBound,
                    upperBound: upperBound
                )
            )
            lowerBound = upperBound + 1
            index += 1
        }
        return segments.count > 1
            ? segments
            : nil
    }

    private static func apply(
        _ rawValue: String,
        to directive:
            inout DirectSegmentDirective
    ) {
        let value = rawValue.trimmed
        guard !value.isEmpty else {
            directive.enabled = true
            return
        }

        let lower = value.lowercased()
        if [
            "0",
            "false",
            "no",
            "off",
            "none",
            "disable",
            "disabled"
        ].contains(lower) {
            directive.enabled = false
            directive.count = nil
            return
        }
        if [
            "1",
            "true",
            "yes",
            "on",
            "enable",
            "enabled"
        ].contains(lower) {
            directive.enabled = true
            return
        }
        if let count = Int(lower),
           count > 1 {
            directive.enabled = true
            directive.count = count
            return
        }

        let pairs =
            lower
            .split(separator: ",")
            .map {
                String($0).trimmed
            }
            .filter {
                !$0.isEmpty
            }
        for pair in pairs {
            guard let separator =
                    pair.firstIndex(
                        of: "="
                    ) else {
                continue
            }
            let key =
                String(
                    pair[..<separator]
                )
                .trimmed
            let value =
                String(
                    pair[
                        pair.index(
                            after: separator
                        )...
                    ]
                )
                .trimmed
            if [
                "n",
                "count",
                "segments",
                "segment",
                "split"
            ].contains(key),
               let count = Int(value),
               count > 1 {
                directive.enabled = true
                directive.count = count
            } else if [
                "enabled",
                "enable",
                "on"
            ].contains(key) {
                apply(
                    value,
                    to: &directive
                )
            }
        }
    }

    private static let defaultChunkSize =
        1_048_576
}
