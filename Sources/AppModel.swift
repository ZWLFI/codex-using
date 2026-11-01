import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var selectedBucketID = ""
    @Published private(set) var forecast: ForecastResult?
    @Published private(set) var risk: RiskLevel = .unknown
    @Published var dashboardTab: DashboardTab = .overview

    let settings: AppSettings
    private let client = CodexAppServerClient()
    private let notifications = NotificationService()
    private var samples: [UsageSample]
    private var dailyPercentState: DailyPercentState
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    init(settings: AppSettings) {
        self.settings = settings
        LocalStore.migrateLegacyDefaultsIfNeeded()
        snapshot = LocalStore.load(DashboardSnapshot.self, from: AppFiles.state)
        samples = LocalStore.load([UsageSample].self, from: AppFiles.samples) ?? []
        dailyPercentState = DailyPercentStorage.load()
        selectedBucketID = snapshot?.rateLimits.buckets.first?.id ?? ""
        recomputeDerived()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var buckets: [RateLimitBucket] { snapshot?.rateLimits.buckets ?? [] }
    var selectedBucket: RateLimitBucket? {
        buckets.first(where: { $0.id == selectedBucketID }) ?? buckets.first
    }
    var selectedWindow: RateLimitWindow? { selectedBucket?.activeWindow }
    var remainingPercent: Double? {
        guard selectedWindow?.usedPercent != nil else { return nil }
        return selectedWindow?.remainingPercent
    }
    var latestDaily: DailyUsageBucket? { UsageStatistics.latest(snapshot?.usage.dailyUsageBuckets ?? []) }
    var dailyPercentPoints7: [DailyPercentPoint] {
        DailyPercentTracker.points(dailyPercentState, bucketID: selectedBucket?.id ?? "codex")
    }
    var insight: String { UsageStatistics.insight(snapshot?.usage.dailyUsageBuckets ?? []) }
    var summary: UsageSummary? { snapshot?.usage.summary }
    var dataIsStale: Bool {
        guard let fetchedAt = snapshot?.fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= 15 * 60
    }

    var menuTitle: String {
        let remaining = DisplayFormat.percent(remainingPercent)
        switch settings.menuStyle {
        case .compact:
            return remaining
        case .standard:
            return "GPT \(remaining)"
        case .full:
            let countdown = shortCountdown(selectedWindow?.resetDate)
            return "GPT \(remaining) · \(countdown)"
        }
    }

    var coverageText: String {
        guard let latest = latestDaily, let date = latest.date else { return "尚无每日 token 数据" }
        return "数据更新至 \(DisplayFormat.day.string(from: date))"
    }

    var refreshText: String {
        if isRefreshing { return "正在更新…" }
        if let error = lastError { return "更新失败 · \(error)" }
        guard let date = snapshot?.fetchedAt else { return "等待更新" }
        return "已更新 · \(DisplayFormat.dateTime.string(from: date))"
    }

    var forecastText: String {
        guard let forecast else { return "样本不足，暂无预测" }
        if forecast.exhaustsBeforeReset {
            return "预计 \(DisplayFormat.dateTime.string(from: forecast.exhaustedAt)) 耗尽"
        }
        return "按当前速度可用至重置后"
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await client.setRateLimitChangeHandler { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
        timer = .scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let (rateLimits, usage, path) = try await client.fetch()
                apply(DashboardSnapshot(fetchedAt: Date(), rateLimits: rateLimits, usage: usage, codexPath: path))
            } catch {
                fail(error)
            }
        }
    }

    func selectBucket(_ id: String) {
        selectedBucketID = id
        recomputeDerived()
    }

    func requestNotificationAuthorization() {
        Task {
            let granted = await notifications.requestAuthorization()
            if !granted { settings.notificationsEnabled = false }
        }
    }

    func sendTestNotification() {
        Task { try? await notifications.sendTest() }
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
    }

    var diagnosticsText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let bucketCount = snapshot?.rateLimits.buckets.count ?? 0
        let latest = latestDaily?.startDate ?? "none"
        return """
        GPT 用量 \(version)
        codexPath=\(snapshot?.codexPath ?? (try? CodexLocator.resolve()) ?? "not-found")
        fetchedAt=\(snapshot.map { ISO8601DateFormatter().string(from: $0.fetchedAt) } ?? "never")
        lastError=\(lastError ?? "none")
        consecutiveFailures=\(consecutiveFailures)
        rateLimitBuckets=\(bucketCount)
        latestDailyBucket=\(latest)
        cache=\(AppFiles.state.path)
        """
    }

    private func apply(_ newSnapshot: DashboardSnapshot) {
        let previous = snapshot
        snapshot = newSnapshot
        isRefreshing = false
        lastError = nil
        consecutiveFailures = 0
        if !newSnapshot.rateLimits.buckets.contains(where: { $0.id == selectedBucketID }) {
            selectedBucketID = newSnapshot.rateLimits.buckets.first?.id ?? ""
        }
        appendSamples(from: newSnapshot)
        for bucket in newSnapshot.rateLimits.buckets {
            guard let usedPercent = bucket.activeWindow?.usedPercent,
                  let resetsAt = bucket.activeWindow?.resetsAt else { continue }
            DailyPercentTracker.update(
                &dailyPercentState,
                bucketID: bucket.id,
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                sampledAt: newSnapshot.fetchedAt
            )
        }
        recomputeDerived()
        try? LocalStore.save(newSnapshot, to: AppFiles.state)
        try? LocalStore.save(samples, to: AppFiles.samples)
        try? LocalStore.save(dailyPercentState, to: AppFiles.dailyPercent)
        let bucket = selectedBucket
        let preferences = settings.notificationPreferences
        let forecast = forecast
        Task {
            await notifications.evaluate(
                current: newSnapshot,
                previous: previous,
                forecast: forecast,
                bucket: bucket,
                preferences: preferences
            )
        }
    }

    private func fail(_ error: Error) {
        isRefreshing = false
        lastError = error.localizedDescription
        consecutiveFailures += 1
        let preferences = settings.notificationPreferences
        let failures = consecutiveFailures
        Task { await notifications.notifyReadFailure(count: failures, preferences: preferences) }
    }

    private func appendSamples(from snapshot: DashboardSnapshot) {
        let now = snapshot.fetchedAt
        for bucket in snapshot.rateLimits.buckets {
            guard let used = bucket.activeWindow?.usedPercent,
                  let reset = bucket.activeWindow?.resetsAt else { continue }
            let last = samples.last(where: { $0.bucketId == bucket.id })
            if let last,
               now.timeIntervalSince(last.date) < 60,
               last.usedPercent == used,
               abs(last.resetsAt - reset) < 1 { continue }
            samples.append(UsageSample(date: now, bucketId: bucket.id, usedPercent: used, resetsAt: reset))
        }
        let cutoff = now.addingTimeInterval(-8 * 86_400)
        samples = Array(samples.filter { $0.date >= cutoff }.suffix(2_016))
    }

    private func recomputeDerived() {
        forecast = ForecastCalculator.calculate(samples: samples, bucket: selectedBucket)
        risk = ForecastCalculator.risk(bucket: selectedBucket, forecast: forecast, fetchedAt: snapshot?.fetchedAt)
    }

    private func shortCountdown(_ date: Date?) -> String {
        guard let date else { return "—" }
        let hours = max(0, Int(date.timeIntervalSinceNow / 3_600))
        if hours >= 24 { return "\(hours / 24)天" }
        return "\(hours)小时"
    }
}

