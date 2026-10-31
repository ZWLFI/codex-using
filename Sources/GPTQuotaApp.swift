import ServiceManagement
import SwiftUI

@main
struct GPTQuotaApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--login-status") {
            let status: String
            switch SMAppService.mainApp.status {
            case .notRegistered: status = "notRegistered"
            case .enabled: status = "enabled"
            case .requiresApproval: status = "requiresApproval"
            case .notFound: status = "notFound"
            @unknown default: status = "unknown"
            }
            print(status)
            exit(0)
        }
        if CommandLine.arguments.contains("--live-test") {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                let client = CodexAppServerClient()
                do {
                    let (limits, usage, path) = try await client.fetch()
                    let primary = limits.buckets.first?.activeWindow
                    let latest = UsageStatistics.latest(usage.dailyUsageBuckets ?? [])
                    print("remaining=\(Int(primary?.remainingPercent.rounded() ?? 0))% buckets=\(limits.buckets.count) latest=\(latest?.startDate ?? "none") tokens=\(latest?.tokens ?? 0) path=\(path)")
                    await client.stop()
                } catch {
                    print("live-test failed: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            exit(0)
        }

        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, settings: settings)
        } label: {
            StatusLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Window("GPT 用量", id: "dashboard") {
            DashboardView(model: model, settings: settings)
        }
        .defaultSize(width: 900, height: 650)
    }
}

