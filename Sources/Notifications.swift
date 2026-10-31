import Foundation
import UserNotifications

struct NotificationPreferences: Sendable {
    let enabled: Bool
    let thresholds: [Int]
    let quietHoursEnabled: Bool
    let quietStartMinutes: Int
    let quietEndMinutes: Int
}

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let dedupeKey = "v2.sentNotifications"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    }

    func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "GPT 用量提醒已启用"
        content.body = "之后将在配额紧张或重置时提醒你。"
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "gpt-quota-test", content: content, trigger: nil))
    }

    func evaluate(
        current: DashboardSnapshot,
        previous: DashboardSnapshot?,
        forecast: ForecastResult?,
        bucket: RateLimitBucket?,
        preferences: NotificationPreferences,
        now: Date = Date()
    ) async {
        guard preferences.enabled, !isQuiet(preferences, now: now), let bucket else { return }
        let reset = Int(bucket.activeWindow?.resetsAt ?? 0)
        let used = Int((bucket.activeWindow?.usedPercent ?? 0).rounded())

        for threshold in preferences.thresholds where used >= threshold {
            await notifyOnce(
                key: "threshold.\(bucket.id).\(reset).\(threshold)",
                title: "Codex 配额已使用 \(used)%",
                body: threshold >= 95 ? "配额已非常紧张，建议优先完成当前任务。" : "剩余 \(max(0, 100 - used))%，\(DisplayFormat.countdown(to: bucket.activeWindow?.resetDate)) 后重置。"
            )
        }

        if let forecast, forecast.exhaustsBeforeReset {
            await notifyOnce(
                key: "forecast.\(bucket.id).\(reset)",
                title: "Codex 配额可能提前耗尽",
                body: "按当前速度，预计 \(DisplayFormat.dateTime.string(from: forecast.exhaustedAt)) 耗尽。"
            )
        }

        if let previousBucket = previous?.rateLimits.buckets.first(where: { $0.id == bucket.id }),
           let oldUsed = previousBucket.activeWindow?.usedPercent,
           let oldReset = previousBucket.activeWindow?.resetsAt,
           let newUsed = bucket.activeWindow?.usedPercent,
           let newReset = bucket.activeWindow?.resetsAt,
           newUsed < oldUsed, newReset != oldReset {
            await notifyOnce(
                key: "reset.\(bucket.id).\(Int(newReset))",
                title: "Codex 配额已重置",
                body: "当前已使用 \(Int(newUsed.rounded()))%。"
            )
        }

        if let earliest = current.rateLimits.rateLimitResetCredits?.credits?
            .compactMap(\.expiryDate).filter({ $0 > now }).min(),
           earliest.timeIntervalSince(now) <= 72 * 3_600 {
            await notifyOnce(
                key: "credit-expiry.\(Int(earliest.timeIntervalSince1970))",
                title: "Codex 重置券即将过期",
                body: "最早一张将于 \(DisplayFormat.dateTime.string(from: earliest)) 过期。"
            )
        }
    }

    func notifyReadFailure(count: Int, preferences: NotificationPreferences) async {
        guard preferences.enabled, count == 3, !isQuiet(preferences, now: Date()) else { return }
        await notifyOnce(
            key: "read-failure.\(DayKey.key(for: Date()))",
            title: "GPT 用量连续更新失败",
            body: "已显示最后成功数据，请打开诊断页查看原因。"
        )
    }

    private func notifyOnce(key: String, title: String, body: String) async {
        var sent = Set(UserDefaults.standard.stringArray(forKey: dedupeKey) ?? [])
        guard !sent.contains(key) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            sent.insert(key)
            UserDefaults.standard.set(Array(sent.suffix(100)), forKey: dedupeKey)
        } catch {
            return
        }
    }

    private func isQuiet(_ preferences: NotificationPreferences, now: Date) -> Bool {
        guard preferences.quietHoursEnabled else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = preferences.quietStartMinutes
        let end = preferences.quietEndMinutes
        if start == end { return true }
        return start < end ? (start..<end).contains(minute) : (minute >= start || minute < end)
    }
}

