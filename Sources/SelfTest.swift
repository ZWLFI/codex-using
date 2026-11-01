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

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var dailyState = DailyPercentState(
            baselines: [
                "codex": DailyPercentBaseline(
                    usedPercent: 40,
                    resetsAt: 100,
                    sampledAt: ISO8601DateFormatter().date(from: "2026-10-31T23:58:00Z")!
                )
            ]
        )
        DailyPercentTracker.update(
            &dailyState,
            bucketID: "codex",
            usedPercent: 42,
            resetsAt: 100,
            sampledAt: ISO8601DateFormatter().date(from: "2026-11-01T00:03:00Z")!,
            calendar: calendar
        )
        DailyPercentTracker.update(
            &dailyState,
            bucketID: "codex",
            usedPercent: 50,
            resetsAt: 100,
            sampledAt: ISO8601DateFormatter().date(from: "2026-11-01T00:08:00Z")!,
            calendar: calendar
        )
        DailyPercentTracker.update(
            &dailyState,
            bucketID: "codex",
            usedPercent: 5,
            resetsAt: 200,
            sampledAt: ISO8601DateFormatter().date(from: "2026-11-01T00:13:00Z")!,
            calendar: calendar
        )
        let dailyPoints = DailyPercentTracker.points(
            dailyState,
            bucketID: "codex",
            days: 7,
            endingAt: ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!,
            calendar: calendar
        )
        precondition(dailyPoints.count == 7)
        precondition(dailyPoints.last?.value == 15)

        // A reset invalidates the displayed forecast even when its snapshot is recent.
        let futureReset = now.addingTimeInterval(3_600)
        precondition(QuotaDataState.resolve(fetchedAt: now, resetDate: futureReset, hasError: false, now: now) == .current)
        precondition(QuotaDataState.resolve(fetchedAt: now, resetDate: now, hasError: false, now: now) == .resetPending)
        precondition(QuotaDataState.resolve(fetchedAt: now, resetDate: futureReset, hasError: true, now: now) == .failed)
        precondition(QuotaDataState.resolve(fetchedAt: nil, resetDate: nil, hasError: false, now: now) == .waiting)
        precondition(QuotaDataState.resolve(fetchedAt: nil, resetDate: nil, hasError: true, now: now) == .failed)
        precondition(QuotaDataState.resolve(fetchedAt: now.addingTimeInterval(-900), resetDate: futureReset, hasError: false, now: now) == .cached)

        let firstDay = DayKey.date(from: "2026-11-01", calendar: calendar)!
        let missingDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let lastDay = calendar.date(byAdding: .day, value: 2, to: firstDay)!
        let chartPoints = [
            DayPoint(key: "2026-11-01", date: firstDay, tokens: 0),
            DayPoint(key: "2026-11-03", date: lastDay, tokens: 100)
        ]
        precondition(UsageChartSelection.point(on: firstDay.addingTimeInterval(3_600), in: chartPoints, calendar: calendar)?.tokens == 0)
        precondition(UsageChartSelection.point(on: missingDay, in: chartPoints, calendar: calendar) == nil)
        precondition(UsageChartSelection.point(on: firstDay, in: [], calendar: calendar) == nil)
        let singleDomain = UsageChartSelection.domain(for: [chartPoints[0]], calendar: calendar)!
        precondition(singleDomain.lowerBound == calendar.startOfDay(for: firstDay))
        precondition(singleDomain.upperBound == calendar.startOfDay(for: missingDay))
        precondition(UsageChartSelection.domain(for: [], calendar: calendar) == nil)
        precondition(DisplayFormat.observedPercent(0.4) == "0.4%")
        precondition(DisplayFormat.observedPercent(1.25) == "1.25%")
        precondition(DisplayFormat.observedPercent(0) == "0%")
        precondition(DisplayFormat.observedPercent(nil) == "—")
        let plot = CGRect(x: 30, y: 12, width: 240, height: 100)
        precondition(UsageChartSelection.plotX(at: CGPoint(x: 31, y: 20), in: plot) == 1)
        for outside in [CGPoint(x: 29, y: 20), CGPoint(x: 270, y: 20), CGPoint(x: 50, y: 11), CGPoint(x: 50, y: 112)] {
            precondition(UsageChartSelection.plotX(at: outside, in: plot) == nil)
        }
        print("self-test passed")
    }
}

