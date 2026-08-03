enum DownloadJobMetadataMetrics {
    static func estimatedByteCount(for job: DownloadJob) -> Int64 {
        for key in ["byte_count", "content_length", "filesize", "file_size", "total_bytes", "expected_bytes", "size"] {
            if let value = byteCount(from: job.metadata[key]) {
                return value
            }
        }
        return 0
    }

    private static func byteCount(from value: String?) -> Int64? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        if let parsed = Int64(value), parsed >= 0 {
            return parsed
        }
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty, let parsed = Int64(digits), parsed >= 0 else { return nil }
        return parsed
    }
}
