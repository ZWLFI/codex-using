import AppKit
import Foundation

enum SelfTest {
    static func run() {
        let rateFixture = Data("""
        {
          "ordinaryUsageAllowed": true,
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": {"usedPercent": 61, "windowDurationMins": 10080, "resetsAt": 2000000000},
            "secondary": null,
            "credits": {"hasCredits": false, "unlimited": false, "balance": "0"},
            "planType": "prolite",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "primary": {"usedPercent": 61, "windowDurationMins": 10080, "resetsAt": 2000000000},
              "secondary": null,
              "credits": null,
              "planType": "prolite",
              "rateLimitReachedType": null
            },
            "spark": {
              "limitId": "spark",
              "limitName": "Spark",
              "primary": {"usedPercent": 10, "windowDurationMins": 300, "resetsAt": 2000001000},
              "secondary": null,
              "credits": null,
              "planType": "prolite",
              "rateLimitReachedType": null
            }
          },
          "rateLimitResetCredits": {"availableCount": 2, "credits": []}
        }
        """.utf8)
        let usageFixture = Data("""
        {
          "summary": {
            "lifetimeTokens": 3506239194,
            "peakDailyTokens": 229410845,
            "longestRunningTurnSec": 30012,
            "currentStreakDays": 21,
            "longestStreakDays": 21
          },
          "dailyUsageBuckets": [
            {"startDate": "2026-10-29", "tokens": 104855078},
            {"startDate": "2026-10-30", "tokens": 114869535}
          ],
          "threadUsage": null
        }
        """.utf8)

        let decoder = JSONDecoder()
        let rates = try! decoder.decode(RateLimitsResult.self, from: rateFixture)
        let usage = try! decoder.decode(UsageResult.self, from: usageFixture)
        precondition(rates.buckets.count == 2)
        precondition(rates.buckets.first?.id == "codex")
        precondition(rates.buckets.first?.activeWindow?.remainingPercent == 39)
        precondition(rates.rateLimitResetCredits?.availableCount == 2)
        precondition(usage.summary?.lifetimeTokens == 3_506_239_194)
        precondition(usage.dailyUsageBuckets?.last?.tokens == 114_869_535)
        precondition(UsageExport.csv(usage.dailyUsageBuckets ?? []).contains("2026-10-30,114869535"))
        precondition((try! JSONDecoder().decode([DailyUsageBucket].self, from: UsageExport.json(usage.dailyUsageBuckets ?? []))).count == 2)

        let now = DayKey.date(from: "2026-11-01")!
        let points = UsageStatistics.dayPoints(buckets: usage.dailyUsageBuckets ?? [], days: 4, endingAt: now)
        precondition(points.count == 4)
        precondition(points[0].tokens == 104_855_078)
        precondition(points[1].tokens == 114_869_535)
        precondition(points[2].tokens == nil)
        precondition(points[3].tokens == nil)

        let bucket = rates.buckets.first!
        let reset = bucket.activeWindow!.resetsAt!
        let samples = [0, 5, 10, 20].map { minute in
            UsageSample(
                date: now.addingTimeInterval(Double(minute * 60)),
                bucketId: bucket.id,
                usedPercent: 40 + Double(minute) * 0.3,
                resetsAt: reset
            )
        }
        let forecast = ForecastCalculator.calculate(
            samples: samples,
            bucket: bucket,
            now: now.addingTimeInterval(20 * 60)
        )
        precondition(forecast != nil)
        precondition(forecast!.samples == 4)
        precondition(ForecastCalculator.calculate(samples: Array(samples.prefix(3)), bucket: bucket, now: now) == nil)
        precondition(DisplayFormat.tokens(114_869_535) == "114.9M")
        let statusImage = StatusItemArtwork.image(style: .standard, remaining: 39, resetDate: nil)
        precondition(statusImage.size == NSSize(width: 36, height: 22))
        precondition(statusImage.isTemplate)
        print("self-test passed")
    }
}

