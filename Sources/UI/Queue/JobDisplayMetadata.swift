import Foundation

enum JobDisplayMetadata {
    static func durationText(for job: DownloadJob) -> String? {
        guard let seconds = durationSeconds(for: job), seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return formattedDuration(seconds)
    }

    static func byteCountText(for job: DownloadJob) -> String? {
        guard let byteCount = byteCount(for: job), byteCount > 0 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    static func etaText(for job: DownloadJob) -> String? {
        guard job.status == .queued || job.status == .resolving || job.status == .downloading else {
            return nil
        }
        guard let seconds = etaSeconds(for: job), seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return "ETA \(formattedDuration(seconds))"
    }

    static func transferProgressText(for job: DownloadJob) -> String? {
        guard job.status == .downloading else { return nil }
        let metadata = lowercasedMetadata(for: job)
        let isIndeterminateLive = ["live_active", "live_polling"].contains { key in
            ["1", "true", "yes", "on"].contains(metadata[key]?.trimmed.lowercased() ?? "")
        }
        let hasActiveByteTransfer = ["1", "true", "yes", "on"].contains(
            metadata["transfer_active"]?.trimmed.lowercased() ?? ""
        )
        guard hasActiveByteTransfer || job.progress > 0 else {
            return nil
        }

        var parts: [String] = []
        let itemIndex = Int(metadata["transfer_item_index"] ?? "") ?? 1
        let itemCount = Int(metadata["transfer_item_count"] ?? "") ?? 1
        if !isIndeterminateLive, itemCount > 1 {
            parts.append("\(min(itemCount, max(1, itemIndex)))/\(itemCount)")
        } else if !isIndeterminateLive, job.total > 1 {
            parts.append("\(min(job.total, max(0, job.completed)))/\(job.total)")
        }

        let transferFraction = metadata["transfer_fraction"].flatMap(Double.init)
        let total = byteCount(for: job)
        let downloaded = downloadedByteCount(from: metadata)
        let fraction: Double?
        if let transferFraction {
            fraction = transferFraction
        } else if let downloaded, let total, total > 0 {
            fraction = Double(downloaded) / Double(total)
        } else if !isIndeterminateLive {
            fraction = job.progress > 0 ? job.progress : nil
        } else {
            fraction = nil
        }
        if let fraction, fraction.isFinite {
            parts.append(String(format: "%.0f%%", min(1, max(0, fraction)) * 100))
        }

        if let downloaded, downloaded >= 0 {
            let downloadedText = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
            if let total, total > 0 {
                let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                parts.append("\(downloadedText) / \(totalText)")
            } else {
                parts.append(downloadedText)
            }
        }

        if let speed = speedBytesPerSecond(from: metadata), speed.isFinite, speed > 0 {
            let speedText = ByteCountFormatter.string(
                fromByteCount: Int64(min(Double(Int64.max), speed)),
                countStyle: .file
            )
            parts.append("\(speedText)/s")
        }
        if let seconds = etaSeconds(for: job), seconds.isFinite, seconds >= 0 {
            parts.append("ETA \(formattedDuration(seconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func downloadDateText(for job: DownloadJob) -> String? {
        guard job.status == .finished,
              let date = completionDate(for: job) else {
            return nil
        }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    static func completionDate(for job: DownloadJob) -> Date? {
        let keys = ["download_completed_at", "manual_completed_at", "completed_at"]
        let isoFormatter = ISO8601DateFormatter()
        for key in keys {
            guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { continue }
            if let date = isoFormatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func byteCount(for job: DownloadJob) -> Int64? {
        let metadata = lowercasedMetadata(for: job)
        let keys = [
            "byte_count",
            "content_length",
            "filesize",
            "file_size",
            "total_bytes",
            "expected_bytes",
            "size"
        ]
        for key in keys {
            if let value = metadata[key].flatMap(byteCount(from:)) {
                return value
            }
        }
        return nil
    }

    private static func etaSeconds(for job: DownloadJob) -> Double? {
        let metadata = lowercasedMetadata(for: job)
        for key in ["eta_seconds", "eta", "remaining_seconds", "remaining", "time_remaining"] {
            if let value = metadata[key].flatMap(durationSeconds) {
                return value
            }
        }
        if let raw = metadata["eta_ms"]?.trimmed,
           let milliseconds = Double(raw),
           milliseconds >= 0 {
            return milliseconds / 1000
        }

        guard let byteCount = byteCount(for: job),
              let bytesPerSecond = speedBytesPerSecond(from: metadata),
              bytesPerSecond > 0 else {
            return nil
        }

        if let downloaded = downloadedByteCount(from: metadata), downloaded >= 0 {
            return max(0, Double(byteCount - min(byteCount, downloaded)) / bytesPerSecond)
        }

        guard job.progress > 0, job.progress < 1 else {
            return nil
        }
        return Double(byteCount) * max(0, 1 - job.progress) / bytesPerSecond
    }

    private static func downloadedByteCount(from metadata: [String: String]) -> Int64? {
        for key in ["downloaded_bytes", "downloaded", "completed_bytes", "received_bytes"] {
            if let value = metadata[key].flatMap(byteCount(from:)) {
                return value
            }
        }
        return nil
    }

    private static func speedBytesPerSecond(from metadata: [String: String]) -> Double? {
        for key in ["speed_bytes_per_second", "bytes_per_second", "download_speed", "speed", "bps"] {
            if let raw = metadata[key]?.trimmed,
               let byteCount = byteCount(from: raw) {
                return Double(byteCount)
            }
        }
        return nil
    }

    private static func byteCount(from raw: String) -> Int64? {
        var value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: ",", with: "")
        if let direct = Int64(value), direct >= 0 {
            return direct
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*([kmgtp]?i?b|bytes?|[kmgtp])?"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Double(value[numberRange]),
              number >= 0 else {
            return nil
        }
        let unit = Range(match.range(at: 2), in: value).map { String(value[$0]) } ?? ""
        let multiplier: Double
        switch unit {
        case "", "b", "byte", "bytes":
            multiplier = 1
        case "k", "kb":
            multiplier = 1_000
        case "m", "mb":
            multiplier = 1_000_000
        case "g", "gb":
            multiplier = 1_000_000_000
        case "t", "tb":
            multiplier = 1_000_000_000_000
        case "p", "pb":
            multiplier = 1_000_000_000_000_000
        case "kib":
            multiplier = 1_024
        case "mib":
            multiplier = 1_048_576
        case "gib":
            multiplier = 1_073_741_824
        case "tib":
            multiplier = 1_099_511_627_776
        case "pib":
            multiplier = 1_125_899_906_842_624
        default:
            return nil
        }
        let bytes = number * multiplier
        guard bytes <= Double(Int64.max) else {
            return nil
        }
        return Int64(bytes.rounded())
    }

    private static func durationSeconds(for job: DownloadJob) -> Double? {
        let metadata = lowercasedMetadata(for: job)
        let isLive = ["live", "is_live", "was_live"].contains { key in
            ["1", "true", "yes", "on"].contains(metadata[key]?.trimmed.lowercased() ?? "")
        }
        if isLive,
           let value = metadata["live_recorded_duration"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration_seconds"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration_string"].flatMap(durationSeconds) {
            return value
        }
        if let raw = metadata["duration_ms"]?.trimmed,
           let milliseconds = Double(raw),
           milliseconds >= 0 {
            return milliseconds / 1000
        }
        return nil
    }

    private static func lowercasedMetadata(for job: DownloadJob) -> [String: String] {
        var metadata: [String: String] = [:]
        for (key, value) in job.metadata {
            metadata[key.lowercased()] = value
        }
        return metadata
    }

    private static func durationSeconds(from raw: String) -> Double? {
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

    private static func compoundDurationSeconds(from value: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(ms|h|m|s)"#) else {
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
            consumed += String(value[wholeRange])
            switch String(value[unitRange]) {
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

    private static func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}
