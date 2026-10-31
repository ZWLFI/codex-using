import Foundation

enum ForecastCalculator {
    static func calculate(
        samples: [UsageSample],
        bucket: RateLimitBucket?,
        now: Date = Date()
    ) -> ForecastResult? {
        guard let bucket,
              let window = bucket.activeWindow,
              let currentUsed = window.usedPercent,
              let resetAt = window.resetsAt,
              currentUsed < 100 else { return nil }

        let matching = samples
            .filter {
                $0.bucketId == bucket.id &&
                abs($0.resetsAt - resetAt) < 300 &&
                $0.date <= now
            }
            .sorted { $0.date < $1.date }
        guard matching.count >= 4,
              let first = matching.first,
              let last = matching.last else { return nil }

        let span = last.date.timeIntervalSince(first.date)
        let delta = last.usedPercent - first.usedPercent
        guard span >= 15 * 60, delta >= 2 else { return nil }

        let percentPerSecond = delta / span
        guard percentPerSecond > 0 else { return nil }
        let remainingSeconds = (100 - currentUsed) / percentPerSecond
        let exhaustedAt = now.addingTimeInterval(remainingSeconds)
        return ForecastResult(
            samples: matching.count,
            percentPerHour: percentPerSecond * 3_600,
            exhaustedAt: exhaustedAt,
            resetsAt: Date(timeIntervalSince1970: resetAt)
        )
    }

    static func risk(
        bucket: RateLimitBucket?,
        forecast: ForecastResult?,
        fetchedAt: Date?,
        now: Date = Date()
    ) -> RiskLevel {
        guard let fetchedAt, now.timeIntervalSince(fetchedAt) < 15 * 60,
              let used = bucket?.activeWindow?.usedPercent else { return .unknown }
        if used >= 95 || forecast?.exhaustsBeforeReset == true { return .critical }
        if used >= 80 { return .watch }
        if let forecast,
           forecast.exhaustedAt.timeIntervalSince(forecast.resetsAt) < 24 * 3_600 {
            return .watch
        }
        return .healthy
    }
}

enum UsageStatistics {
    static func dayPoints(
        buckets: [DailyUsageBucket],
        days: Int,
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayPoint] {
        let values = Dictionary(uniqueKeysWithValues: buckets.map { ($0.startDate, $0.tokens) })
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = DayKey.key(for: date, calendar: calendar)
            return DayPoint(key: key, date: date, tokens: values[key])
        }
    }

    static func latest(_ buckets: [DailyUsageBucket]) -> DailyUsageBucket? {
        buckets.max { $0.startDate < $1.startDate }
    }

    static func average(_ buckets: [DailyUsageBucket], days: Int) -> Int64? {
        let values = buckets.sorted { $0.startDate < $1.startDate }.suffix(days).map(\.tokens)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }

    static func insight(_ buckets: [DailyUsageBucket]) -> String {
        let sorted = buckets.sorted { $0.startDate < $1.startDate }
        let recent = sorted.suffix(7).map(\.tokens)
        let previous = sorted.dropLast(recent.count).suffix(7).map(\.tokens)
        guard recent.count >= 3 else { return "继续使用后将生成趋势洞察" }
        if previous.count >= 3 {
            let currentTotal = recent.reduce(0, +)
            let previousTotal = previous.reduce(0, +)
            if previousTotal > 0 {
                let change = (Double(currentTotal) / Double(previousTotal) - 1) * 100
                if abs(change) < 5 { return "近 7 日用量与上一周基本持平" }
                return "近 7 日用量较上一周\(change > 0 ? "增加" : "减少") \(Int(abs(change).rounded()))%"
            }
        }
        if let peak = recent.max(), let average = average(sorted, days: 7) {
            return "近 7 日峰值 \(DisplayFormat.tokens(peak))，日均 \(DisplayFormat.tokens(average))"
        }
        return "已建立真实 token 使用趋势"
    }
}

