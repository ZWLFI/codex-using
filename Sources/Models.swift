import Foundation

struct RateLimitWindow: Codable, Hashable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?

    var remainingPercent: Double { max(0, min(100, 100 - (usedPercent ?? 0))) }
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

struct Credits: Codable, Hashable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?
}

struct RateLimitBucket: Codable, Hashable, Identifiable {
    let limitId: String
    let limitName: String?
    let normalModelSlug: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: Credits?
    let planType: String?
    let rateLimitReachedType: String?

    var id: String { limitId }
    var displayName: String {
        if let limitName, !limitName.isEmpty { return limitName }
        if limitId == "codex" { return "Codex" }
        return limitId.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var activeWindow: RateLimitWindow? { primary ?? secondary }
    var planName: String {
        switch planType?.lowercased() {
        case "pro", "prolite": return "Pro"
        case "plus": return "Plus"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case let value?: return value.capitalized
        case nil: return "ChatGPT"
        }
    }
}

struct RateLimitResetCredit: Codable, Hashable, Identifiable {
    let id: String
    let resetType: String?
    let status: String?
    let grantedAt: TimeInterval?
    let expiresAt: TimeInterval?
    let title: String?
    let description: String?

    var expiryDate: Date? { expiresAt.map(Date.init(timeIntervalSince1970:)) }
}

struct RateLimitResetCredits: Codable, Hashable {
    let availableCount: Int?
    let credits: [RateLimitResetCredit]?
}

struct RateLimitsResult: Codable, Hashable {
    let ordinaryUsageAllowed: Bool?
    let rateLimits: RateLimitBucket?
    let rateLimitsByLimitId: [String: RateLimitBucket]?
    let rateLimitResetCredits: RateLimitResetCredits?

    var buckets: [RateLimitBucket] {
        let values = Array(rateLimitsByLimitId?.values ?? Dictionary<String, RateLimitBucket>().values)
        if values.isEmpty { return rateLimits.map { [$0] } ?? [] }
        return values.sorted {
            if $0.limitId == "codex" { return true }
            if $1.limitId == "codex" { return false }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

struct UsageSummary: Codable, Hashable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
}

struct DailyUsageBucket: Codable, Hashable, Identifiable {
    let startDate: String
    let tokens: Int64

    var id: String { startDate }
    var date: Date? { DayKey.date(from: startDate) }
}

struct UsageResult: Codable, Hashable {
    let summary: UsageSummary?
    let dailyUsageBuckets: [DailyUsageBucket]?
}

struct DashboardSnapshot: Codable, Hashable {
    let fetchedAt: Date
    let rateLimits: RateLimitsResult
    let usage: UsageResult
    let codexPath: String
}

struct UsageSample: Codable, Hashable {
    let date: Date
    let bucketId: String
    let usedPercent: Double
    let resetsAt: TimeInterval
}

struct DailyPercentBaseline: Codable, Hashable {
    var usedPercent: Double
    var resetsAt: TimeInterval
    var sampledAt: Date
}

struct DailyPercentState: Codable, Hashable {
    var valuesByBucket: [String: [String: Double]] = [:]
    var baselines: [String: DailyPercentBaseline] = [:]
}

struct DailyPercentPoint: Identifiable, Hashable {
    let key: String
    let date: Date
    let value: Double?

    var id: String { key }
}

enum DailyPercentTracker {
    static func update(
        _ state: inout DailyPercentState,
        bucketID: String,
        usedPercent: Double,
        resetsAt: TimeInterval,
        sampledAt: Date,
        calendar: Calendar = .current
    ) {
        let current = max(0, min(100, usedPercent))
        let day = DayKey.key(for: sampledAt, calendar: calendar)
        defer {
            state.baselines[bucketID] = DailyPercentBaseline(
                usedPercent: current,
                resetsAt: resetsAt,
                sampledAt: sampledAt
            )
        }

        guard let previous = state.baselines[bucketID] else { return }
        let previousDay = DayKey.key(for: previous.sampledAt, calendar: calendar)
        if previousDay != day, sampledAt.timeIntervalSince(previous.sampledAt) > 15 * 60 {
            return
        }

        let delta: Double
        if current >= previous.usedPercent {
            delta = current - previous.usedPercent
        } else if abs(resetsAt - previous.resetsAt) > 60 {
            delta = current
        } else {
            delta = 0
        }
        guard delta > 0 else { return }

        var values = state.valuesByBucket[bucketID] ?? [:]
        values[day, default: 0] += delta
        let cutoff = calendar.date(byAdding: .day, value: -90, to: sampledAt) ?? sampledAt
        values = values.filter { entry in
            guard let date = DayKey.date(from: entry.key, calendar: calendar) else { return false }
            return date >= cutoff
        }
        state.valuesByBucket[bucketID] = values
    }

    static func points(
        _ state: DailyPercentState,
        bucketID: String,
        days: Int = 7,
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyPercentPoint] {
        let values = state.valuesByBucket[bucketID] ?? [:]
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - days + 1, to: end) else { return nil }
            let key = DayKey.key(for: date, calendar: calendar)
            return DailyPercentPoint(key: key, date: date, value: values[key])
        }
    }
}

enum QuotaDataState: Equatable {
    case current, waiting, failed, cached, resetPending

    static func resolve(fetchedAt: Date?, resetDate: Date?, hasError: Bool, now: Date = Date()) -> Self {
        if hasError { return .failed }
        guard let fetchedAt else { return .waiting }
        if let resetDate, resetDate <= now { return .resetPending }
        if now.timeIntervalSince(fetchedAt) >= 15 * 60 { return .cached }
        return .current
    }

    var title: String {
        switch self {
        case .current: return "已更新"
        case .waiting: return "等待数据"
        case .failed: return "更新失败"
        case .cached: return "缓存数据"
        case .resetPending: return "重置待更新"
        }
    }
}

enum RiskLevel: String, Codable {
    case healthy
    case watch
    case critical
    case unknown

    var title: String {
        switch self {
        case .healthy: return "状态良好"
        case .watch: return "需要关注"
        case .critical: return "配额紧张"
        case .unknown: return "数据不可用"
        }
    }
}

struct ForecastResult: Hashable {
    let samples: Int
    let percentPerHour: Double
    let exhaustedAt: Date
    let resetsAt: Date

    var exhaustsBeforeReset: Bool { exhaustedAt < resetsAt }
}

struct DayPoint: Identifiable, Hashable {
    let key: String
    let date: Date
    let tokens: Int64?

    var id: String { key }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case history = "历史"
    case settings = "设置与诊断"

    var id: String { rawValue }
}

enum MenuDisplayStyle: String, CaseIterable, Identifiable {
    case compact
    case standard
    case full

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .full: return "完整"
        }
    }
}

enum DayKey {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2], hour: 12))
    }
}

enum DisplayFormat {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static func tokens(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let number = Double(value)
        if number >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
        if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if number >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return String(value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func observedPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) + "%"
    }

    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "等待更新" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "即将重置" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }
}

