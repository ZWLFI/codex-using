import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

enum AppFiles {
    static let directory: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("GPT 用量", isDirectory: true)
    }()
    static let state = directory.appendingPathComponent("state.json")
    static let samples = directory.appendingPathComponent("samples.json")
    static let dailyPercent = directory.appendingPathComponent("daily-percent.json")
    static let legacy = directory.appendingPathComponent("legacy-v1.3.json")

    static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

enum LocalStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        try AppFiles.prepare()
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: "dataMigrationVersion") < 2 else { return }
        let legacy: [String: Any] = [
            "dailyUsage": defaults.dictionary(forKey: "dailyUsage") ?? [:],
            "lastUsedPercent": defaults.object(forKey: "lastUsedPercent") ?? NSNull(),
            "quotaReset": defaults.object(forKey: "quotaReset") ?? NSNull(),
            "migratedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if JSONSerialization.isValidJSONObject(legacy),
           let data = try? JSONSerialization.data(withJSONObject: legacy, options: [.prettyPrinted, .sortedKeys]) {
            try? AppFiles.prepare()
            try? data.write(to: AppFiles.legacy, options: .atomic)
        }
        defaults.set(2, forKey: "dataMigrationVersion")
    }
}

private struct LegacyDailyPercentState: Decodable {
    let dailyUsage: [String: Double]
    let lastUsedPercent: Double?
    let quotaReset: TimeInterval?
    let migratedAt: Date
}

enum DailyPercentStorage {
    static func load() -> DailyPercentState {
        if let current = LocalStore.load(DailyPercentState.self, from: AppFiles.dailyPercent) {
            return current
        }
        guard let legacy = LocalStore.load(LegacyDailyPercentState.self, from: AppFiles.legacy) else {
            return DailyPercentState()
        }

        var state = DailyPercentState(valuesByBucket: ["codex": legacy.dailyUsage])
        if let usedPercent = legacy.lastUsedPercent, let resetsAt = legacy.quotaReset {
            state.baselines["codex"] = DailyPercentBaseline(
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                sampledAt: legacy.migratedAt
            )
        }
        return state
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let menuStyle = "v2.menuStyle"
        static let notifications = "v2.notifications"
        static let threshold70 = "v2.threshold70"
        static let threshold85 = "v2.threshold85"
        static let threshold95 = "v2.threshold95"
        static let quietHours = "v2.quietHours"
        static let quietStart = "v2.quietStart"
        static let quietEnd = "v2.quietEnd"
    }

    private var loading = true
    @Published var menuStyle: MenuDisplayStyle = .standard { didSet { persist() } }
    @Published var notificationsEnabled = false { didSet { persist() } }
    @Published var threshold70 = true { didSet { persist() } }
    @Published var threshold85 = true { didSet { persist() } }
    @Published var threshold95 = true { didSet { persist() } }
    @Published var quietHoursEnabled = true { didSet { persist() } }
    @Published var quietStartMinutes = 22 * 60 { didSet { persist() } }
    @Published var quietEndMinutes = 8 * 60 { didSet { persist() } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchStatus = "未启用"

    init(defaults: UserDefaults = .standard) {
        menuStyle = MenuDisplayStyle(rawValue: defaults.string(forKey: Key.menuStyle) ?? "") ?? .standard
        notificationsEnabled = defaults.bool(forKey: Key.notifications)
        threshold70 = defaults.object(forKey: Key.threshold70) == nil ? true : defaults.bool(forKey: Key.threshold70)
        threshold85 = defaults.object(forKey: Key.threshold85) == nil ? true : defaults.bool(forKey: Key.threshold85)
        threshold95 = defaults.object(forKey: Key.threshold95) == nil ? true : defaults.bool(forKey: Key.threshold95)
        quietHoursEnabled = defaults.object(forKey: Key.quietHours) == nil ? true : defaults.bool(forKey: Key.quietHours)
        quietStartMinutes = defaults.object(forKey: Key.quietStart) == nil ? 22 * 60 : defaults.integer(forKey: Key.quietStart)
        quietEndMinutes = defaults.object(forKey: Key.quietEnd) == nil ? 8 * 60 : defaults.integer(forKey: Key.quietEnd)
        loading = false
        refreshLaunchStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refreshLaunchStatus()
            launchStatus = error.localizedDescription
            return
        }
        refreshLaunchStatus()
    }

    func refreshLaunchStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            launchStatus = "已启用"
        case .requiresApproval:
            launchAtLogin = true
            launchStatus = "需在系统设置中批准"
        case .notRegistered:
            launchAtLogin = false
            launchStatus = "未启用"
        case .notFound:
            launchAtLogin = false
            launchStatus = "应用位置不可用"
        @unknown default:
            launchAtLogin = false
            launchStatus = "未知"
        }
    }

    var notificationPreferences: NotificationPreferences {
        NotificationPreferences(
            enabled: notificationsEnabled,
            thresholds: [
                threshold70 ? 70 : nil,
                threshold85 ? 85 : nil,
                threshold95 ? 95 : nil
            ].compactMap { $0 },
            quietHoursEnabled: quietHoursEnabled,
            quietStartMinutes: quietStartMinutes,
            quietEndMinutes: quietEndMinutes
        )
    }

    private func persist() {
        guard !loading else { return }
        let defaults = UserDefaults.standard
        defaults.set(menuStyle.rawValue, forKey: Key.menuStyle)
        defaults.set(notificationsEnabled, forKey: Key.notifications)
        defaults.set(threshold70, forKey: Key.threshold70)
        defaults.set(threshold85, forKey: Key.threshold85)
        defaults.set(threshold95, forKey: Key.threshold95)
        defaults.set(quietHoursEnabled, forKey: Key.quietHours)
        defaults.set(quietStartMinutes, forKey: Key.quietStart)
        defaults.set(quietEndMinutes, forKey: Key.quietEnd)
    }
}

enum ExportFormat: String {
    case csv
    case json
}

enum UsageExport {
    static func csv(_ buckets: [DailyUsageBucket]) -> String {
        (["date,tokens"] + buckets.map { "\($0.startDate),\($0.tokens)" })
            .joined(separator: "\n") + "\n"
    }

    static func json(_ buckets: [DailyUsageBucket]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(buckets)
    }
}

@MainActor
enum ExportService {
    static func export(_ snapshot: DashboardSnapshot, format: ExportFormat, range: Int?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GPT-用量-\(DayKey.key(for: Date())).\(format.rawValue)"
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.canCreateDirectories = true
        let window = NSApp.keyWindow
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let buckets = filtered(snapshot.usage.dailyUsageBuckets ?? [], range: range)
            do {
                switch format {
                case .csv:
                    try UsageExport.csv(buckets).write(to: url, atomically: true, encoding: .utf8)
                case .json:
                    try UsageExport.json(buckets).write(to: url, options: .atomic)
                }
            } catch {
                if let window {
                    NSAlert(error: error).beginSheetModal(for: window)
                } else {
                    NSApp.presentError(error)
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private static func filtered(_ buckets: [DailyUsageBucket], range: Int?) -> [DailyUsageBucket] {
        let sorted = buckets.sorted { $0.startDate < $1.startDate }
        guard let range else { return sorted }
        return Array(sorted.suffix(range))
    }
}

