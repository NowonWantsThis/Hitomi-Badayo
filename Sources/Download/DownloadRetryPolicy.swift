import Foundation

enum ScheduledRetryKind: String {
    case restart
    case incomplete
    case release
    case imported
}

struct DownloadRetryPolicy {
    static let timestampMetadataKey = "t_retry"
    static let originalTitleMetadataKey = "retry_original_title"
    static let kindMetadataKey = "retry_kind"
    static let delayMetadataKey = "retry_delay_seconds"
    static let forceMetadataKey = "retry_force"

    static func failureAllowsIncompleteRetry(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let bridgeError = error as? PythonScriptBridgeError {
            if case .retryRequested = bridgeError {
                return false
            }
            return true
        }
        if let nativeError = error as? NativeDownloadError {
            switch nativeError {
            case .invalidURL, .unsupported, .missingGalleryID, .encryptedPlaylist, .cancelled:
                return false
            case .httpStatus(let status, _):
                return status == 408 || status == 425 || status == 429 || status >= 500
            case .invalidGalleryData, .noFiles, .invalidPlaylist:
                return true
            }
        }
        if let urlError = error as? URLError {
            return [
                URLError.Code.timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .internationalRoamingOff,
                .callIsActive,
                .dataNotAllowed,
                .resourceUnavailable
            ].contains(urlError.code)
        }
        return true
    }

    static func releaseRetryTimestamp(for job: DownloadJob) -> TimeInterval? {
        for key in ["release_timestamp", "hdt_release_timestamp"] {
            guard let raw = job.metadata[key]?.trimmed, !raw.isEmpty else { continue }
            if let value = Double(raw), value.isFinite {
                return value
            }
            if let date = ISO8601DateFormatter().date(from: raw) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    static func scheduledRetryTimestamp(from metadata: [String: String]) -> TimeInterval? {
        guard let raw = metadata[timestampMetadataKey]?.trimmed,
              let value = Double(raw),
              value.isFinite,
              value > 1 else {
            return nil
        }
        return value
    }

    static func remainingSeconds(
        target: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Int {
        max(0, Int(target - now + 0.5))
    }

    static func countdownTitle(
        target: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970,
        identifier: String
    ) -> String? {
        let total = remainingSeconds(target: target, now: now)
        guard total > 0 else { return nil }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return "Restart in \(days)d \(hours)h \(minutes)m \(seconds)s: \(identifier)"
        }
        if hours > 0 {
            return "Restart in \(hours)h \(minutes)m \(seconds)s: \(identifier)"
        }
        if minutes > 0 {
            return "Restart in \(minutes)m \(seconds)s: \(identifier)"
        }
        return "Restart in \(seconds)s: \(identifier)"
    }

    static func isEligible(_ job: DownloadJob, kind: ScheduledRetryKind) -> Bool {
        guard job.status != .resolving, job.status != .downloading else { return false }
        if kind == .restart {
            return job.status == .finished
        }
        return true
    }

    static func timestampString(_ value: TimeInterval) -> String {
        if value.rounded() == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(format: "%.6f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    static func metadataBool(_ raw: String?) -> Bool {
        guard let raw = raw?.trimmed.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}
