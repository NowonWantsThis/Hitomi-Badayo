import Foundation

enum HitomiTasterService {
    static func referenceCount(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        bookmarks: [URLBookmark]
    ) -> Int {
        ArtistRecommendationService.referenceCount(
            jobs: jobs,
            history: history,
            bookmarks: bookmarks
        )
    }

    static func results(
        recommendations: [ArtistRecommendation],
        model: HitomiTasterModel,
        referenceCount: Int,
        limit: Int = 80
    ) -> [HitomiTasterResult] {
        recommendations
            .map { recommendation in
                let signalCount = max(
                    1,
                    recommendation.jobCount +
                        recommendation.historyCount +
                        recommendation.bookmarkCount
                )
                let termCount = Double(recommendation.relatedTerms.count)
                let recencyDays = recommendation.lastSeen.map {
                    max(0, -$0.timeIntervalSinceNow / 86_400)
                } ?? 90
                let recencyBoost = max(0, 2.0 - recencyDays / 45.0)
                let adjusted: Double
                switch model {
                case .shallow:
                    adjusted = recommendation.score +
                        log1p(Double(signalCount)) * 0.7 +
                        termCount * 0.15 +
                        recencyBoost * 0.2
                case .deep:
                    adjusted = recommendation.score *
                        (1 + min(termCount, 8) * 0.055) +
                        sqrt(Double(signalCount)) * 1.4 +
                        recencyBoost * 0.45 +
                        (recommendation.bookmarkCount > 0 ? 0.4 : 0)
                }
                let confidence = min(
                    99.0,
                    max(
                        1.0,
                        42.0 + adjusted * 3.2 +
                            Double(min(referenceCount, 80)) * 0.28 +
                            (model == .deep ? 5 : 0)
                    )
                )
                return (
                    recommendation: recommendation,
                    adjusted: adjusted,
                    confidence: confidence
                )
            }
            .sorted {
                if $0.adjusted != $1.adjusted {
                    return $0.adjusted > $1.adjusted
                }
                return $0.recommendation.name.localizedStandardCompare(
                    $1.recommendation.name
                ) == .orderedAscending
            }
            .prefix(max(0, limit))
            .enumerated()
            .map { offset, item in
                HitomiTasterResult(
                    rank: offset + 1,
                    recommendation: item.recommendation,
                    model: model,
                    adjustedScore: item.adjusted,
                    confidence: item.confidence
                )
            }
    }

    static func accuracy(
        results: [HitomiTasterResult],
        referenceCount: Int,
        model: HitomiTasterModel
    ) -> Double {
        guard !results.isEmpty else { return 0 }
        let top = results.prefix(20)
        let averageConfidence = top.reduce(0) {
            $0 + $1.confidence
        } / Double(top.count)
        let referenceBoost = min(8, Double(referenceCount) * 0.16)
        let modelBoost = model == .deep ? 2.5 : 0
        return min(
            99.5,
            max(1, averageConfidence * 0.72 + referenceBoost + modelBoost)
        )
    }
}
